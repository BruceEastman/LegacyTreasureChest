//
//  ScannerHelpView.swift
//  LegacyTreasureChest
//
//  Dedicated help screen for scanning paper documents into a PDF.
//  This is user guidance only (no automation).
//

import SwiftUI

struct ScannerHelpView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                header

                VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("When to Use Documents")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            bullet("Receipts, appraisals, provenance letters, certificates, and repair records.")
                            bullet("Anything an executor might need later to explain value or ownership.")
                            bullet("For many items, one PDF is enough.")
                        }
                        .ltcCardBackground()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Option A (Simple): Scan and Attach")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                            step("1", "Scan a PDF", "Use either Notes or Files to scan the document into a PDF.")
                            step("2", "Open the item in LTC", "Go to the item you are documenting.")
                            step("3", "Attach the PDF", "Use the Documents section to import/attach the PDF from Files.")
                        }
                        .ltcCardBackground()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Option B (Optional): One Folder + Consistent Names")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            Text("If you want an easy-to-find paper trail, you can keep all PDFs in one folder with consistent filenames.")
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)

                            bullet("Create a folder in Files called “LTC Documents”.")
                            bullet("Store one PDF per item, named predictably (example: “LTC - Jequel Painting.pdf”).")
                            bullet("Then, when attaching documents in LTC, you can search by item name and find the right PDF quickly.")
                        }
                        .ltcCardBackground()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("How to Scan on iPhone")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                            subheader("Notes App Scan")
                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                bullet("Open Notes and create/open a note.")
                                bullet("Tap the camera icon → Scan Documents.")
                                bullet("Scan → Save.")
                                bullet("Share/Export → Save to Files as a PDF (optional).")
                            }

                            subheader("Files App Scan (direct to PDF)")
                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                bullet("Open Files and navigate to your desired folder.")
                                bullet("Tap the … menu → Scan Documents.")
                                bullet("Scan → Save (creates a PDF in that folder).")
                                bullet("Rename immediately so it is easy to find later.")
                            }
                        }
                        .ltcCardBackground()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Scanning Tips for Clean PDFs")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            bullet("Use soft, even light. Avoid glare (especially on glossy receipts).")
                            bullet("Use a dark, non-reflective background so the page edges are easy to detect.")
                            bullet("Flatten pages and hold the phone directly overhead.")
                            bullet("Before saving, adjust corners if needed. Use Color or Grayscale for faint text.")
                            bullet("For multi-page items, scan all pages into one PDF.")
                        }
                        .ltcCardBackground()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("If You Accidentally Saved PDFs in the Wrong Place")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                            step("1", "Open Files", "Open Files → Recents (or find where the PDFs are).")
                            step("2", "Select PDFs", "Long-press one PDF → Select → tap others to select multiple.")
                            step("3", "Move", "Tap the … menu → Move → choose your folder → Move.")
                            step("4", "Rename", "Long-press a PDF → Rename → use a clear item-based name.")
                        }
                        .ltcCardBackground()
                    }

                    footerNote
                }
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Scanning & Documents")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Scanning & Documents")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("A practical way to capture receipts and records without friction.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.spacing.small)
    }

    private var footerNote: some View {
        Text("If you prefer simplicity: scan the PDF, then attach it to the item in LTC. The folder approach is optional.")
            .font(Theme.secondaryFont)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, Theme.spacing.small)
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.small) {
            Text("•")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 12, alignment: .leading)

            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func subheader(_ text: String) -> some View {
        Text(text)
            .font(Theme.bodyFont.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.top, Theme.spacing.small)
    }

    @ViewBuilder
    private func step(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.medium) {
            Text(number)
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                Text(title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Text(body)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
