//
//  LTCModels.swift
//  LegacyTreasureChest
//
//  SwiftData models for Legacy Treasure Chest.
//  iOS 18+, Swift 6.
//

import Foundation
import SwiftData

// MARK: - Enums (non-model types)

public enum AccessPermission: String, Codable, CaseIterable, Sendable {
    case immediate = "Immediate"
    case afterSpecificDate = "AfterSpecificDate"
    case uponPassing = "UponPassing"
}

public enum NotificationStatus: String, Codable, CaseIterable, Sendable {
    case notSent = "NotSent"
    case sent = "Sent"
    case accepted = "Accepted"
}

// MARK: - User

@Model
public final class LTCUser {
    @Attribute(.unique) public var userId: UUID
    @Attribute(.unique) public var appleUserIdentifier: String
    public var email: String?
    public var name: String?
    public var createdAt: Date
    public var updatedAt: Date
    
    // Relationships
    @Relationship(deleteRule: .cascade) public var items: [LTCItem] = []
    @Relationship(deleteRule: .cascade) public var beneficiaries: [Beneficiary] = []
    
    public init(
        userId: UUID = UUID(),
        appleUserIdentifier: String,
        email: String? = nil,
        name: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userId = userId
        self.appleUserIdentifier = appleUserIdentifier
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Item

@Model
public final class LTCItem {
    @Attribute(.unique) public var itemId: UUID
    public var name: String
    public var itemDescription: String
    public var category: String
    public var value: Double
    public var createdAt: Date
    public var updatedAt: Date
    
    // AI-generated fields (optional)
    public var llmGeneratedTitle: String?
    public var llmGeneratedDescription: String?
    public var suggestedPriceNew: Double?
    public var suggestedPriceUsed: Double?
    
    // Relationships (user is optional to avoid creation crashes)
    @Relationship(inverse: \LTCUser.items) public var user: LTCUser?
    @Relationship(deleteRule: .cascade) public var images: [ItemImage] = []
    @Relationship(deleteRule: .cascade) public var audioRecordings: [AudioRecording] = []
    @Relationship(deleteRule: .cascade) public var documents: [Document] = []
    @Relationship(deleteRule: .cascade) public var itemBeneficiaries: [ItemBeneficiary] = []
    
    public init(
        itemId: UUID = UUID(),
        name: String,
        itemDescription: String,
        category: String,
        value: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.itemId = itemId
        self.name = name
        self.itemDescription = itemDescription
        self.category = category
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ItemImage

@Model
public final class ItemImage {
    @Attribute(.unique) public var imageId: UUID
    public var filePath: String          // Relative path to image file
    public var createdAt: Date
    
    @Relationship(inverse: \LTCItem.images) public var item: LTCItem?
    
    public init(
        imageId: UUID = UUID(),
        filePath: String,
        createdAt: Date = .now
    ) {
        self.imageId = imageId
        self.filePath = filePath
        self.createdAt = createdAt
    }
}

// MARK: - AudioRecording

@Model
public final class AudioRecording {
    @Attribute(.unique) public var audioRecordingId: UUID
    public var filePath: String          // Relative path to audio file
    public var duration: Double          // Seconds
    public var transcription: String?    // Apple Intelligence transcription
    public var createdAt: Date
    public var updatedAt: Date
    
    @Relationship(inverse: \LTCItem.audioRecordings) public var item: LTCItem?
    
    public init(
        audioRecordingId: UUID = UUID(),
        filePath: String,
        duration: Double,
        transcription: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.audioRecordingId = audioRecordingId
        self.filePath = filePath
        self.duration = duration
        self.transcription = transcription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Document

@Model
public final class Document {
    @Attribute(.unique) public var documentId: UUID
    public var filePath: String          // Relative path to document file
    public var documentType: String
    public var originalFilename: String? // Human-friendly name as chosen by user
    public var createdAt: Date
    
    @Relationship(inverse: \LTCItem.documents) public var item: LTCItem?
    
    public init(
        documentId: UUID = UUID(),
        filePath: String,
        documentType: String,
        originalFilename: String? = nil,
        createdAt: Date = .now
    ) {
        self.documentId = documentId
        self.filePath = filePath
        self.documentType = documentType
        self.originalFilename = originalFilename
        self.createdAt = createdAt
    }
}

// MARK: - Beneficiary

@Model
public final class Beneficiary {
    @Attribute(.unique) public var beneficiaryId: UUID
    public var name: String
    public var relationship: String
    public var email: String?
    public var phoneNumber: String?
    public var contactIdentifier: String?   // CNContact identifier (advisory only)
    public var isLinkedToContact: Bool
    public var createdAt: Date
    public var updatedAt: Date
    
    @Relationship(inverse: \LTCUser.beneficiaries) public var user: LTCUser?
    @Relationship(deleteRule: .cascade) public var itemLinks: [ItemBeneficiary] = []
    
    public init(
        beneficiaryId: UUID = UUID(),
        name: String,
        relationship: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        contactIdentifier: String? = nil,
        isLinkedToContact: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.beneficiaryId = beneficiaryId
        self.name = name
        self.relationship = relationship
        self.email = email
        self.phoneNumber = phoneNumber
        self.contactIdentifier = contactIdentifier
        self.isLinkedToContact = isLinkedToContact
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ItemBeneficiary (junction entity)

@Model
public final class ItemBeneficiary {
    @Attribute(.unique) public var itemBeneficiaryId: UUID
    public var accessPermissionRaw: String
    public var accessDate: Date?
    public var personalMessage: String?
    public var notificationStatusRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    
    @Relationship(inverse: \LTCItem.itemBeneficiaries) public var item: LTCItem?
    @Relationship(inverse: \Beneficiary.itemLinks) public var beneficiary: Beneficiary?
    
    public var accessPermission: AccessPermission {
        get { AccessPermission(rawValue: accessPermissionRaw) ?? .immediate }
        set { accessPermissionRaw = newValue.rawValue }
    }
    
    public var notificationStatus: NotificationStatus {
        get { NotificationStatus(rawValue: notificationStatusRaw) ?? .notSent }
        set { notificationStatusRaw = newValue.rawValue }
    }
    
    public init(
        itemBeneficiaryId: UUID = UUID(),
        accessPermission: AccessPermission,
        accessDate: Date? = nil,
        personalMessage: String? = nil,
        notificationStatus: NotificationStatus = .notSent,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.itemBeneficiaryId = itemBeneficiaryId
        self.accessPermissionRaw = accessPermission.rawValue
        self.accessDate = accessDate
        self.personalMessage = personalMessage
        self.notificationStatusRaw = notificationStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
