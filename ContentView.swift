import SwiftUI
import MapKit

struct ContentView: View {
    var body: some View {
        TabView{
            
            //@State private var currentActiveIndex = 0
            
            mapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
            
            zonesView()
                .tabItem {
                    Label("Zones", systemImage: "exclamationmark.triangle.fill")
                }
            
            routeView()
                .tabItem {
                    Label("Route", systemImage: "location.fill")
                }
            
            delaysView()
                .tabItem {
                    Label("Delays", systemImage: "aqi.high")
                }
        }
    }
}

struct mapView: View {
    var body: some View {
        Text("Test text: Map view (home screen)")
    }
}

struct zonesView: View {
    var body: some View {
        Text("Test text: Zones view (commonly flooded areas)")
    }
}

struct routeView: View {
    var body: some View {
        Text("Test text: Route view (routing around real-time floods)")
    }
}

struct delaysView: View {
    var body: some View {
        Text("Test text: Delays view (real-time flooding delays")
    }
}
