//
//  CreateGroupView.swift
//  FreeSplitUnlimited
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CreateGroupView: View {
    var onCreated: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var kind: GroupKind?
    @State private var friends: [FriendDraft]
    @State private var photoItem: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var coverImageData: Data?
    @State private var showingFriendPicker = false
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker

    init(onCreated: @escaping (UUID) -> Void = { _ in }) {
        self.onCreated = onCreated
        _friends = State(initialValue: [FriendDraft(contact: ContactDirectory.me())])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identityCard
                    kindSection
                    peopleSection

                    Button {
                        createGroup()
                    } label: {
                        Text("Create Group")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.teal)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("createGroupSubmit")
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFriendPicker) {
                FriendSearchPicker(
                    contactsAllowed: contactsAllowed,
                    savedFriends: KnownFriendsStore.previouslyUsedFriends(from: modelContext),
                    onPick: { contacts in
                        add(contacts)
                    },
                    onContactsAccessGranted: {
                        contactsAllowed = true
                    }
                )
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(from: item) }
            }
        }
        .tint(AppTheme.teal)
    }

    private var identityCard: some View {
        HStack(alignment: .center, spacing: 16) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    Circle()
                        .fill(AppTheme.lightAqua)

                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.deepTeal)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.teal, lineWidth: 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppTheme.teal)
                        .background(Circle().fill(Color.white).padding(2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a group photo")

            VStack(alignment: .leading, spacing: 10) {
                TextField("Name this group", text: $name)
                    .textInputAutocapitalization(.words)
                    .font(.headline)
                    .accessibilityIdentifier("groupNameField")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField("Short note (optional)", text: $note)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kind of group")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(GroupKind.allCases) { option in
                    Button {
                        kind = option
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: option.symbol)
                                .font(.title2)
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(kind == option ? Color.white : AppTheme.deepTeal)
                        .background(
                            kind == option ? AppTheme.teal : Color.white.opacity(0.86),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(friends.filter(\.isComplete)) { friend in
                    HStack {
                        Image(systemName: friend.trimmedName.localizedCaseInsensitiveCompare("Me") == .orderedSame
                              ? "person.crop.circle.fill"
                              : "person.crop.circle")
                            .foregroundStyle(AppTheme.teal)
                        Text(friend.trimmedName)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    Task { await presentFriendPicker() }
                } label: {
                    Label("Add people", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(showingFriendPicker)
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @MainActor
    private func presentFriendPicker() async {
        guard !showingFriendPicker else { return }
        await ContactAuthorization.requestIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        guard !showingFriendPicker else { return }
        contactsAllowed = ContactAuthorization.canUseSystemPicker
        showingFriendPicker = true
    }

    private func add(_ contacts: [PickedContact]) {
        var next: [FriendDraft] = []
        for contact in contacts {
            let draft = FriendDraft(contact: contact)
            let alreadyAdded = next.contains {
                $0.trimmedName.localizedCaseInsensitiveCompare(draft.trimmedName) == .orderedSame
            }
            if !alreadyAdded {
                next.append(draft)
            }
        }
        for existing in friends where existing.isComplete {
            let alreadyAdded = next.contains {
                $0.trimmedName.localizedCaseInsensitiveCompare(existing.trimmedName) == .orderedSame
            }
            if !alreadyAdded {
                next.append(existing)
            }
        }
        friends = next
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let prepared = Self.preparedCover(from: image)
        await MainActor.run {
            coverImage = prepared.image
            coverImageData = prepared.data
        }
    }

    private static func preparedCover(from image: UIImage) -> (image: UIImage, data: Data?) {
        let maxSide: CGFloat = 512
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return (resized, resized.jpegData(compressionQuality: 0.72))
    }

    private func createGroup() {
        guard canCreate else { return }

        let occasion = Occasion(
            name: trimmedName,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            groupType: (kind ?? .other).rawValue
        )

        var people = friends.filter(\.isComplete).map {
            Person(
                name: $0.trimmedName,
                email: $0.email.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: $0.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if !people.contains(where: { $0.name.localizedCaseInsensitiveCompare("Me") == .orderedSame }) {
            people.insert(Person(name: "Me"), at: 0)
        }

        occasion.members = people
        JoinCode.assignIfNeeded(to: occasion, in: modelContext)
        modelContext.insert(occasion)
        GroupCoverStore.save(coverImageData, for: occasion.id)
        modelContext.persist()
        let id = occasion.id
        dismiss()
        onCreated(id)
    }
}