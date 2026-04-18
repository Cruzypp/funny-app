import SwiftUI

struct EmergencySheet: View {
    @Environment(AppRouter.self) var router
    @Environment(\.dismiss) var dismiss
    
    @State private var timeLeft = 10
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header con contador
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(T.risk.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(timeLeft) / 10.0)
                        .stroke(T.risk, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1.0), value: timeLeft)
                    
                    Text("\(timeLeft)")
                        .font(.serif(40))
                        .foregroundStyle(T.risk)
                }
                .padding(.top, 20)
                
                Text("Iniciando auxilio automático")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(T.pri(router.night))
                
                Text("Si no seleccionas una opción, llamaremos al 911 por ti.")
                    .font(.system(size: 14))
                    .foregroundStyle(T.sec(router.night))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                // Botón 911
                CaminosButton(label: "Llamar al 911 ahora", icon: "phone.fill", variant: .primary) {
                    callNumber("911")
                }
                .background(T.risk, in: RoundedRectangle(cornerRadius: 18))
                
                Divider().padding(.vertical, 8)
                
                Text("CONTACTOS DE CONFIANZA")
                    .font(.mono(11))
                    .foregroundStyle(T.sec(router.night))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if router.contacts.isEmpty {
                    Text("Aun no has agregado contactos de confianza.")
                        .font(.system(size: 14))
                        .foregroundStyle(T.sec(router.night))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(T.surface(router.night), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(router.contacts) { contact in
                                Button {
                                    callNumber(contact.phone)
                                } label: {
                                    HStack {
                                        Circle().fill(contact.color).frame(width: 32, height: 32)
                                            .overlay(Text(String(contact.name.prefix(1))).foregroundStyle(.white).font(.system(size: 12, weight: .bold)))

                                        VStack(alignment: .leading) {
                                            Text(contact.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(T.pri(router.night))
                                            Text(contact.phone)
                                                .font(.system(size: 13))
                                                .foregroundStyle(T.sec(router.night))
                                        }
                                        Spacer()
                                        Image(systemName: "phone.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(T.safe)
                                    }
                                    .padding()
                                    .background(T.surface(router.night), in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                Button("Cancelar") {
                    stopTimer()
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(T.sec(router.night))
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(.top, 20)
        .background(T.bg(router.night))
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
            } else {
                stopTimer()
                callNumber("911")
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func callNumber(_ phone: String) {
        stopTimer()
        var cleanPhone = phone.filter { "0123456789".contains($0) }
        
        // Remove country code (+52 or 52) if present
        if cleanPhone.hasPrefix("52") && cleanPhone.count > 10 {
            cleanPhone = String(cleanPhone.dropFirst(2))
        }
        
        if let url = URL(string: "tel://\(cleanPhone)") {
            UIApplication.shared.open(url)
        }
        dismiss()
    }
}
