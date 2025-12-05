//
//  ContactPickerView.swift
//  LegacyTreasureChest
//
//  SwiftUI wrapper around CNContactPickerViewController.
//  Used to pick a person from Contacts and return CNContact to SwiftUI.
//

import SwiftUI
import ContactsUI

struct ContactPickerView: UIViewControllerRepresentable {
    var onSelect: (CNContact) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator

        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactMiddleNameKey,
            CNContactOrganizationNameKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey
        ]

        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {
        // No dynamic updates needed.
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (CNContact) -> Void,
             onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
