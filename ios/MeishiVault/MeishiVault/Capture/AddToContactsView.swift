import SwiftUI
import ContactsUI
import Contacts
import MeishiKit

/// Card を Apple 連絡先の「新規連絡先」画面に流し込む。
/// 実際の保存はユーザーがシステム UI で行うため、事前の権限要求は不要。
struct AddToContactsView: UIViewControllerRepresentable {
    let card: Card
    let imageData: Data?
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: makeContact())
        controller.delegate = context.coordinator
        controller.contactStore = CNContactStore()
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    private func makeContact() -> CNMutableContact {
        let contact = CNMutableContact()
        contact.familyName = card.familyName ?? ""
        contact.givenName = card.givenName ?? ""
        contact.phoneticFamilyName = card.familyNameKana ?? ""
        contact.phoneticGivenName = card.givenNameKana ?? ""
        contact.organizationName = card.company ?? ""
        contact.departmentName = card.department ?? ""
        contact.jobTitle = card.title ?? ""
        if let imageData { contact.imageData = imageData }

        if let email = card.email, !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }

        var phones: [CNLabeledValue<CNPhoneNumber>] = []
        if let phone = card.phone, !phone.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: phone)))
        }
        if let mobile = card.mobile, !mobile.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: mobile)))
        }
        if let fax = card.fax, !fax.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberWorkFax, value: CNPhoneNumber(stringValue: fax)))
        }
        contact.phoneNumbers = phones

        if (card.address?.isEmpty == false) || (card.postalCode?.isEmpty == false) {
            let address = CNMutablePostalAddress()
            address.street = card.address ?? ""
            address.postalCode = card.postalCode ?? ""
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: address)]
        }

        if let url = card.url, !url.isEmpty {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelWork, value: url as NSString)]
        }

        return contact
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onFinish()
        }
    }
}
