import Foundation
import Observation
import CoreLocation

struct PlaceSuggestion: Identifiable, Codable {
    let id: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case id = "place_id"
        case description
    }
}

@Observable
final class GooglePlacesManager {
    var suggestions: [PlaceSuggestion] = []
    private let apiKey = "TU_API_KEY_AQUI" // Reemplaza con tu llave real
    
    func search(query: String) async {
        guard !query.isEmpty else {
            self.suggestions = []
            return
        }
        
        let urlString = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=\(query)&key=\(apiKey)&components=country:mx"
        
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PredictionsResponse.self, from: data)
            
            await MainActor.run {
                self.suggestions = response.predictions
            }
        } catch {
            print("Error en búsqueda de Google Places: \(error)")
        }
    }
}

struct PredictionsResponse: Codable {
    let predictions: [PlaceSuggestion]
}
