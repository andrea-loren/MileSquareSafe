import SwiftUI
import MapKit

// MARK: - SECTION 1: Data Models
enum AppTransportMode: String, CaseIterable, Identifiable {
    case walking = "Walking"
    case driving = "Driving"
    case transit = "Transit"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        case .transit: return "bus.fill"
        }
    }
    
    var mkType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .driving: return .automobile
        case .transit: return .transit
        }
    }
}

struct FloodPoint: Identifiable {
    let id = UUID()
    let name: String
    let severity: String
    let coordinate: CLLocationCoordinate2D
    let isUserReported: Bool
}

struct DelayReport: Identifiable {
    let id = UUID()
    let title: String
    let location: String
    let delayMinutes: Int
    let description: String
    let coordinate: CLLocationCoordinate2D?
    var notThereVotes: Int = 0
}

// MARK: - SECTION 2: NWS API JSON Models
struct NWSAlertResponse: Codable {
    let features: [NWSFeature]?
}

struct NWSFeature: Codable {
    let properties: NWSProperties?
}

struct NWSProperties: Codable {
    let event: String?
    let headline: String?
    let description: String?
}

// MARK: - SECTION 3: Central Data Manager
@Observable
class FloodDataManager {
    var points: [FloodPoint] = []
    var delayReports: [DelayReport] = []
    
    var activeWeatherAlert: String? = nil
    var isLoadingAlerts: Bool = false
    
    func addUserReport(name: String, severity: String, latitude: Double, longitude: Double) {
        let newPoint = FloodPoint(
            name: name,
            severity: severity,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            isUserReported: true
        )
        points.append(newPoint)
    }
    
    func voteFloodNotThere(id: UUID) {
        if let index = points.firstIndex(where: { $0.id == id }) {
            points.remove(at: index)
        }
    }
    
    @MainActor
    func fetchLiveAlerts() async {
        isLoadingAlerts = true
        defer { isLoadingAlerts = false }
        
        guard let url = URL(string: "https://api.weather.gov/alerts/active?area=NJ") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("MileSquareSafeApp/1.0 (contact@milesquaresafe.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decodedResponse = try JSONDecoder().decode(NWSAlertResponse.self, from: data)
                let features = decodedResponse.features ?? []
                let floodEvents = features.compactMap { $0.properties?.event }
                
                if let activeEvent = floodEvents.first(where: { $0.localizedCaseInsensitiveContains("Flood") || $0.localizedCaseInsensitiveContains("Rain") }) {
                    activeWeatherAlert = "Alert: \(activeEvent)"
                } else {
                    activeWeatherAlert = "No Active NWS Flood Alerts"
                }
            } else {
                activeWeatherAlert = "No Active NWS Flood Alerts"
            }
        } catch {
            activeWeatherAlert = "No Active NWS Flood Alerts"
        }
    }
    
    func addDelay(title: String, location: String, minutes: Int, description: String, coord: CLLocationCoordinate2D?) {
        let newReport = DelayReport(
            title: title,
            location: location,
            delayMinutes: minutes,
            description: description,
            coordinate: coord ?? CLLocationCoordinate2D(latitude: 40.7400, longitude: -74.0320)
        )
        delayReports.append(newReport)
    }
    
    func voteDelayNotThere(id: UUID) {
        if let index = delayReports.firstIndex(where: { $0.id == id }) {
            delayReports[index].notThereVotes += 1
            if delayReports[index].notThereVotes >= 3 {
                delayReports.remove(at: index)
            }
        }
    }
}

// MARK: - SECTION 4: Map Location Picker (Mini-Map for Dropping Pins)
struct LocationPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Binding var locationName: String
    
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7440, longitude: -74.0324),
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
    )
    
    @State private var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 40.7440, longitude: -74.0324)
    
    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition)
                    .onMapCameraChange(frequency: .continuous) { context in
                        centerCoordinate = context.region.center
                    }
                
                VStack(spacing: 2) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.red)
                        .shadow(radius: 3)
                    
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .offset(y: -5)
                    
                    Text("Pan to position pin")
                        .font(.caption2)
                        .bold()
                        .padding(4)
                        .background(.thinMaterial)
                        .cornerRadius(6)
                }
            }
            .navigationTitle("Drop Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        selectedCoordinate = centerCoordinate
                        
                        let request = MKLocalSearch.Request()
                        request.naturalLanguageQuery = "Hoboken, NJ"
                        request.region = MKCoordinateRegion(center: centerCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001))
                        
                        let search = MKLocalSearch(request: request)
                        Task {
                            if let response = try? await search.start(), let item = response.mapItems.first {
                                if let name = item.name {
                                    await MainActor.run {
                                        locationName = name
                                    }
                                }
                            }
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

// MARK: - SECTION 5: Root View (ContentView)
struct ContentView: View {
    @State private var dataManager = FloodDataManager()
    
    var body: some View {
        TabView {
            MapView(dataManager: dataManager)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
            
            ZonesView(dataManager: dataManager)
                .tabItem {
                    Label("Zones", systemImage: "exclamationmark.triangle.fill")
                }
            
            RouteView(dataManager: dataManager)
                .tabItem {
                    Label("Route", systemImage: "location.fill")
                }
            
            DelaysView(dataManager: dataManager)
                .tabItem {
                    Label("Delays", systemImage: "clock.fill")
                }
        }
    }
}

// MARK: - SECTION 6.1: Sub View - MapView
struct MapView: View {
    var dataManager: FloodDataManager
    
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7440, longitude: -74.0324),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    
                    ForEach(dataManager.points) { point in
                        Annotation(point.name, coordinate: point.coordinate) {
                            Image(systemName: point.isUserReported ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                                .foregroundColor(point.isUserReported ? .purple : .red)
                                .font(.title2)
                        }
                    }
                    
                    ForEach(dataManager.delayReports) { delay in
                        if let coord = delay.coordinate {
                            Annotation(delay.title, coordinate: coord) {
                                Image(systemName: "clock.badge.exclamationmark.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                            }
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .ignoresSafeArea(edges: .bottom)
                
                HStack {
                    Text("Map")
                        .font(.title2)
                        .bold()
                    
                    Spacer()
                    
                    if let alert = dataManager.activeWeatherAlert {
                        HStack(spacing: 4) {
                            Image(systemName: "cloud.rain.fill")
                                .font(.caption2)
                            Text(alert)
                                .font(.caption2)
                                .bold()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationBarHidden(true)
            .task {
                await dataManager.fetchLiveAlerts()
            }
        }
    }
}

// MARK: - SECTION 6.2: Sub View - ZonesView
struct ZonesView: View {
    var dataManager: FloodDataManager
    
    @State private var showReportSheet = false
    @State private var spotName = ""
    @State private var severity = "Moderate"
    @State private var selectedCoord: CLLocationCoordinate2D? = nil
    @State private var showPicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Flooded Zones")
                        .font(.title2)
                        .bold()
                    
                    Spacer()
                    
                    Button(action: { showReportSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                List {
                    Section(header: Text("Live NOAA Status")) {
                        HStack {
                            Image(systemName: "cloud.rain.fill")
                                .foregroundColor(.blue)
                            Text(dataManager.activeWeatherAlert ?? "Checking NWS Alerts...")
                                .font(.subheadline)
                        }
                    }
                    
                    Section(header: Text("Reported Flood Points")) {
                        if dataManager.points.isEmpty {
                            Text("No active flood spots reported.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(dataManager.points) { point in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(point.name)
                                                .font(.headline)
                                            Text("Severity: \(point.severity)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if point.isUserReported {
                                            Text("Crowdsourced")
                                                .font(.caption2)
                                                .padding(4)
                                                .background(Color.purple.opacity(0.2))
                                                .foregroundColor(.purple)
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    if point.isUserReported {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                dataManager.voteFloodNotThere(id: point.id)
                                            }) {
                                                Label("Water Cleared", systemImage: "checkmark.circle")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showReportSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Report Flooding Spot")) {
                            TextField("Location Name (e.g. 1st & Garden)", text: $spotName)
                            Picker("Severity", selection: $severity) {
                                Text("Minor").tag("Minor")
                                Text("Moderate").tag("Moderate")
                                Text("Severe").tag("Severe")
                            }
                            
                            Button(action: { showPicker = true }) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(selectedCoord == nil ? "Drop Pin on Map" : "Pin Set ✓")
                                        .bold()
                                }
                                .foregroundColor(selectedCoord == nil ? .blue : .green)
                            }
                        }
                    }
                    .navigationTitle("New Flood Spot")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showReportSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Submit") {
                                let coord = selectedCoord ?? CLLocationCoordinate2D(latitude: 40.7420, longitude: -74.0340)
                                let name = spotName.isEmpty ? "Flooded Area" : spotName
                                
                                dataManager.addUserReport(
                                    name: name,
                                    severity: severity,
                                    latitude: coord.latitude,
                                    longitude: coord.longitude
                                )
                                spotName = ""
                                selectedCoord = nil
                                showReportSheet = false
                            }
                        }
                    }
                    .sheet(isPresented: $showPicker) {
                        LocationPickerView(selectedCoordinate: $selectedCoord, locationName: $spotName)
                    }
                }
            }
        }
    }
}

// MARK: - SECTION 6.3: Sub View - RouteView
struct RouteView: View {
    var dataManager: FloodDataManager
    
    @State private var startLocation: String = "Hoboken Terminal"
    @State private var endLocation: String = "Hoboken Grace"
    
    @State private var startCoord: CLLocationCoordinate2D? = nil
    @State private var endCoord: CLLocationCoordinate2D? = nil
    
    @State private var selectedTransportMode: AppTransportMode = .walking
    
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    
    @State private var selectedRoute: MKRoute? = nil
    @State private var routeDirections: [String] = []
    @State private var isCalculating: Bool = false
    @State private var routeWarning: String? = nil
    
    @State private var routeCameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7440, longitude: -74.0324),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Flood-Safe Routing")
                        .font(.title2)
                        .bold()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
                
                Map(position: $routeCameraPosition) {
                    UserAnnotation()
                    
                    ForEach(dataManager.points) { point in
                        Annotation(point.name, coordinate: point.coordinate) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                        }
                    }
                    
                    if let route = selectedRoute {
                        MapPolyline(route.polyline)
                            .stroke(.blue, lineWidth: 6)
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                
                Form {
                    Section(header: Text("Transport Mode")) {
                        Picker("Mode", selection: $selectedTransportMode) {
                            ForEach(AppTransportMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Section(header: Text("Start Location")) {
                        TextField("Starting Point Name", text: $startLocation)
                        Button(action: { showStartPicker = true }) {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                Text(startCoord == nil ? "Pick Start on Map" : "Start Pin Set ✓")
                                    .bold()
                            }
                            .foregroundColor(startCoord == nil ? .blue : .green)
                        }
                    }
                    
                    Section(header: Text("Destination Location")) {
                        TextField("Destination Name", text: $endLocation)
                        Button(action: { showEndPicker = true }) {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                Text(endCoord == nil ? "Pick End on Map" : "End Pin Set ✓")
                                    .bold()
                            }
                            .foregroundColor(endCoord == nil ? .blue : .green)
                        }
                    }
                    
                    Button(action: {
                        calculateSafeRoute()
                    }) {
                        HStack {
                            if isCalculating {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Label("Calculate Safe Route", systemImage: "location.magnifyingglass")
                                .bold()
                        }
                    }
                    .disabled(isCalculating)
                    
                    if let warning = routeWarning {
                        Section(header: Text("Route Status")) {
                            Text(warning)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if let route = selectedRoute {
                        Section(header: Text("Safe Path Summary")) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(route.name.isEmpty ? "Calculated Path" : route.name)
                                        .font(.headline)
                                    Text("Distance: \(String(format: "%.2f", route.distance / 1609.34)) miles")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Est. Time: \(Int(route.expectedTravelTime / 60)) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Section(header: Text("Step-by-Step Directions")) {
                            ForEach(routeDirections, id: \.self) { step in
                                Text(step)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showStartPicker) {
                LocationPickerView(selectedCoordinate: $startCoord, locationName: $startLocation)
            }
            .sheet(isPresented: $showEndPicker) {
                LocationPickerView(selectedCoordinate: $endCoord, locationName: $endLocation)
            }
        }
    }
    
    private func searchCoordinate(for query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.contains("Hoboken") ? query : "\(query), Hoboken, NJ"
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7440, longitude: -74.0324),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first?.location.coordinate
        } catch {
            return nil
        }
    }
    
    private func calculateSafeRoute() {
        isCalculating = true
        routeWarning = nil
        selectedRoute = nil
        routeDirections = []
        
        Task {
            let origin: CLLocationCoordinate2D?
            if let startCoord = startCoord {
                origin = startCoord
            } else {
                origin = await searchCoordinate(for: startLocation)
            }
            
            let destination: CLLocationCoordinate2D?
            if let endCoord = endCoord {
                destination = endCoord
            } else {
                destination = await searchCoordinate(for: endLocation)
            }
            
            guard let validStart = origin else {
                await MainActor.run {
                    isCalculating = false
                    routeWarning = "Could not locate starting point."
                }
                return
            }
            
            guard let validEnd = destination else {
                await MainActor.run {
                    isCalculating = false
                    routeWarning = "Could not locate destination."
                }
                return
            }
            
            let request = MKDirections.Request()
            request.source = MKMapItem(location: CLLocation(latitude: validStart.latitude, longitude: validStart.longitude), address: nil)
            request.destination = MKMapItem(location: CLLocation(latitude: validEnd.latitude, longitude: validEnd.longitude), address: nil)
            request.transportType = selectedTransportMode.mkType
            request.requestsAlternateRoutes = true
            
            let directions = MKDirections(request: request)
            
            do {
                let response = try await directions.calculate()
                let routes = response.routes
                var chosenRoute: MKRoute? = nil
                
                for route in routes {
                    var intersectsFlood = false
                    
                    for point in dataManager.points {
                        let floodLoc = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
                        let pointCount = route.polyline.pointCount
                        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
                        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
                        
                        for coord in coords {
                            let routeLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                            if routeLoc.distance(from: floodLoc) < 150 {
                                intersectsFlood = true
                                break
                            }
                        }
                        if intersectsFlood { break }
                    }
                    
                    if !intersectsFlood {
                        chosenRoute = route
                        break
                    }
                }
                
                await MainActor.run {
                    isCalculating = false
                    if chosenRoute == nil {
                        chosenRoute = routes.first
                        routeWarning = "Caution: Recommended route passes near reported flooding."
                    }
                    
                    if let finalRoute = chosenRoute {
                        self.selectedRoute = finalRoute
                        self.routeDirections = finalRoute.steps.map { $0.instructions }.filter { !$0.isEmpty }
                        self.routeCameraPosition = .rect(finalRoute.polyline.boundingMapRect)
                    }
                }
            } catch {
                await MainActor.run {
                    isCalculating = false
                    routeWarning = "Unable to compute directions for the selected transport mode."
                }
            }
        }
    }
}

// MARK: - SECTION 6.4: Sub View - DelaysView
struct DelaysView: View {
    var dataManager: FloodDataManager
    
    @State private var showReportSheet = false
    @State private var showPicker = false
    
    @State private var newTitle = ""
    @State private var newLocation = ""
    @State private var newMinutes = ""
    @State private var newDescription = ""
    @State private var selectedCoord: CLLocationCoordinate2D? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Real-time Delays")
                        .font(.title2)
                        .bold()
                    
                    Spacer()
                    
                    Button(action: { showReportSheet = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                List {
                    if dataManager.delayReports.isEmpty {
                        Text("No delay reports currently submitted.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(dataManager.delayReports) { report in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(report.title)
                                        .font(.headline)
                                    Spacer()
                                    Text("+\(report.delayMinutes) min")
                                        .font(.caption)
                                        .bold()
                                        .padding(4)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                                
                                Text(report.location)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(report.description)
                                    .font(.footnote)
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        dataManager.voteDelayNotThere(id: report.id)
                                    }) {
                                        Label("Not Here (\(report.notThereVotes)/3)", systemImage: "hand.thumbsdown")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showReportSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Report a Delay")) {
                            TextField("Title (e.g. Bus Detour)", text: $newTitle)
                            TextField("Location Name", text: $newLocation)
                            
                            Button(action: { showPicker = true }) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(selectedCoord == nil ? "Drop Pin on Map" : "Pin Set ✓")
                                        .bold()
                                }
                                .foregroundColor(selectedCoord == nil ? .blue : .green)
                            }
                            
                            TextField("Delay in Minutes", text: $newMinutes)
                                .keyboardType(.numberPad)
                            TextField("Description", text: $newDescription)
                        }
                    }
                    .navigationTitle("New Delay Report")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showReportSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Submit") {
                                let minutes = Int(newMinutes) ?? 5
                                let title = newTitle.isEmpty ? "Delay Alert" : newTitle
                                let locationText = newLocation.isEmpty ? "Hoboken" : newLocation
                                let finalCoord = selectedCoord ?? CLLocationCoordinate2D(latitude: 40.7440, longitude: -74.0324)
                                
                                dataManager.addDelay(
                                    title: title,
                                    location: locationText,
                                    minutes: minutes,
                                    description: newDescription,
                                    coord: finalCoord
                                )
                                
                                newTitle = ""
                                newLocation = ""
                                newMinutes = ""
                                newDescription = ""
                                selectedCoord = nil
                                showReportSheet = false
                            }
                        }
                    }
                    .sheet(isPresented: $showPicker) {
                        LocationPickerView(selectedCoordinate: $selectedCoord, locationName: $newLocation)
                    }
                }
            }
        }
    }
}
