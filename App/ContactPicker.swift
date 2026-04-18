import SwiftUI
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onSelect: (TrustedContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = contact.givenName.isEmpty ? contact.familyName : contact.givenName
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            
            // Generar un color aleatorio para el avatar
            let colors = ["E07856", "2E7D5B", "3A5998", "C4452E"]
            let randomColor = Color(hex: colors.randomElement() ?? "E07856")
            
            let newContact = TrustedContact(name: name, phone: phone, color: randomColor)
            parent.onSelect(newContact)
            parent.dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.dismiss()
        }
    }
}
