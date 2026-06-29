import SwiftUI
#if canImport(Charts)
import Charts
#endif

// MARK: - Showcase App Entry Point

struct CatalystShowcaseView: View {
    @StateObject private var accent = CatalystAccent()
    @StateObject private var toastManager = CatalystToastManager()
    @StateObject private var dialogManager = CatalystDialogManager()
    @State private var activeNav = "dashboard"

    var body: some View {
        CatalystAppShell {
            CatalystSidebar(title: "Catalyst") {
                CatalystNavList(
                    sections: [
                        CatalystNavSection(items: [
                            CatalystNavItem(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2"),
                        ]),
                        CatalystNavSection(header: "Components", items: [
                            CatalystNavItem(id: "buttons", label: "Buttons"),
                            CatalystNavItem(id: "forms", label: "Forms"),
                            CatalystNavItem(id: "badges", label: "Badges"),
                            CatalystNavItem(id: "autocomplete", label: "Autocomplete"),
                        ]),
                        CatalystNavSection(header: "Data", items: [
                            CatalystNavItem(id: "tables", label: "Tables"),
                            CatalystNavItem(id: "datatable", label: "Data Table"),
                            CatalystNavItem(id: "charts", label: "Charts"),
                        ]),
                        CatalystNavSection(header: "Feedback", items: [
                            CatalystNavItem(id: "toasts", label: "Toasts & Alerts"),
                            CatalystNavItem(id: "dialogs", label: "Dialogs"),
                        ]),
                        CatalystNavSection(header: "Layout", items: [
                            CatalystNavItem(id: "panels", label: "Panels & Grids"),
                            CatalystNavItem(id: "typography", label: "Typography"),
                            CatalystNavItem(id: "colors", label: "Color Palette"),
                        ]),
                    ],
                    activeID: $activeNav
                )
            }
        } content: {
            ShowcaseContent(activeNav: activeNav, toastManager: toastManager, dialogManager: dialogManager)
        }
        .environment(\.catalystAccent, accent)
        .catalystToasts(toastManager)
        .catalystDialogs(dialogManager)
    }
}

// MARK: - Content Router

private struct ShowcaseContent: View {
    let activeNav: String
    let toastManager: CatalystToastManager
    let dialogManager: CatalystDialogManager

    var body: some View {
        switch activeNav {
        case "dashboard":    DashboardSection(toastManager: toastManager)
        case "buttons":      ButtonsSection()
        case "forms":        FormsSection()
        case "badges":       BadgesSection()
        case "autocomplete": AutocompleteSection()
        case "tables":       TablesSection()
        case "datatable":    DataTableSection()
        case "charts":       ChartsSection()
        case "toasts":       ToastsSection(toastManager: toastManager)
        case "dialogs":      DialogsSection(dialogManager: dialogManager)
        case "panels":       PanelsSection()
        case "typography":   TypographySection()
        case "colors":       ColorsSection()
        default:             DashboardSection(toastManager: toastManager)
        }
    }
}

// MARK: - Dashboard

private struct DashboardSection: View {
    let toastManager: CatalystToastManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Dashboard").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))

            CatalystAdaptiveGrid {
                StatCard(title: "Total items", value: "247", badge: "+12%", variant: .success)
                StatCard(title: "Active users", value: "18", badge: nil, variant: nil)
                StatCard(title: "Errors", value: "3", badge: "Critical", variant: .danger)
                StatCard(title: "Uptime", value: "99.7%", badge: "Healthy", variant: .success)
            }

            CatalystAlertBanner(.info, message: "This is a showcase of the Catalyst Design System for SwiftUI.", title: "Welcome")

            CatalystPanel(title: "Recent activity") {
                VStack(alignment: .leading, spacing: Catalyst.Spacing.space2) {
                    ActivityRow(text: "Deployment completed", time: "2m ago", type: .success)
                    ActivityRow(text: "New user registered", time: "15m ago", type: .info)
                    ActivityRow(text: "Disk usage warning", time: "1h ago", type: .warning)
                    ActivityRow(text: "Build failed", time: "3h ago", type: .danger)
                }
            }
        }
    }
}

private struct StatCard: View {
    let title: String; let value: String; let badge: String?; let variant: CatalystBadgeVariant?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        CatalystPanel(title: title) {
            HStack(alignment: .firstTextBaseline, spacing: Catalyst.Spacing.md) {
                Text(value).font(Catalyst.Typography.title1).foregroundColor(Catalyst.Text.primary(scheme))
                if let badge, let variant { CatalystBadge(label: badge, variant: variant) }
            }
        }
    }
}

private struct ActivityRow: View {
    let text: String; let time: String; let type: CatalystAlertType
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: Catalyst.Spacing.space3) {
            Text(type.icon).font(Catalyst.Typography.caption1)
                .foregroundColor(type.accentColor().text(scheme))
                .frame(width: 20, height: 20)
                .background(Circle().fill(type.accentColor().subtle(scheme)))
            Text(text).font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.primary(scheme))
            Spacer()
            Text(time).font(Catalyst.Typography.caption1).foregroundColor(Catalyst.Text.tertiary(scheme))
        }
        .padding(.vertical, Catalyst.Spacing.space1)
    }
}

// MARK: - Buttons

private struct ButtonsSection: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Buttons").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            SectionLabel("Roles")
            HStack(spacing: Catalyst.Spacing.md) {
                CatalystButton("Default") {}
                CatalystButton("Primary", role: .primary) {}
                CatalystButton("Success", role: .success) {}
                CatalystButton("Warning", role: .warning) {}
                CatalystButton("Danger", role: .danger) {}
                CatalystButton("Ghost", role: .ghost) {}
            }
            SectionLabel("Sizes")
            HStack(spacing: Catalyst.Spacing.md) {
                CatalystButton("Small", size: .sm) {}
                CatalystButton("Medium", size: .md) {}
                CatalystButton("Large", size: .lg) {}
            }
            SectionLabel("Verbose labels (Catalyst convention)")
            HStack(spacing: Catalyst.Spacing.md) {
                CatalystButton("Save changes", role: .primary) {}
                CatalystButton("Delete record", role: .danger) {}
                CatalystButton("Cancel") {}
            }
            SectionLabel("Disabled")
            HStack(spacing: Catalyst.Spacing.md) {
                CatalystButton("Disabled primary", role: .primary) {}.disabled(true)
                CatalystButton("Disabled default") {}.disabled(true)
            }
        }
    }
}

// MARK: - Forms

private struct FormsSection: View {
    @Environment(\.colorScheme) private var scheme
    @State private var username = "admin"
    @State private var email = ""
    @State private var notes = ""
    @State private var agreed = false
    @State private var option = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Forms").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            VStack(alignment: .leading, spacing: 0) {
                CatalystFormGroup(label: "Username") {
                    TextField("Enter username", text: $username).textFieldStyle(CatalystTextFieldStyle())
                }
                CatalystFormGroup(label: "Email", hint: "We'll never share your email.") {
                    TextField("Enter email", text: $email).textFieldStyle(CatalystTextFieldStyle())
                }
                CatalystFormGroup(label: "Broken field", error: "This field is required.") {
                    TextField("", text: .constant("")).textFieldStyle(CatalystTextFieldStyle(isError: true))
                }
                CatalystFormGroup(label: "Notes") {
                    TextEditor(text: $notes).font(Catalyst.Typography.body).frame(minHeight: 80).catalystBorder(scheme)
                }
                HStack(spacing: Catalyst.Spacing.space2) {
                    Toggle("", isOn: $agreed).toggleStyle(.checkbox).labelsHidden()
                    Text("I agree to the terms").font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.primary(scheme))
                }
                .padding(.bottom, Catalyst.Spacing.space3)
                Picker("Plan", selection: $option) {
                    Text("Free").tag(0); Text("Pro").tag(1); Text("Enterprise").tag(2)
                }
                .pickerStyle(.segmented).padding(.bottom, Catalyst.Spacing.lg)
                HStack(spacing: Catalyst.Spacing.md) {
                    CatalystButton("Save changes", role: .primary) {}
                    CatalystButton("Cancel") {}
                }
            }
            .frame(maxWidth: 480)
        }
    }
}

// MARK: - Badges

private struct BadgesSection: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Badges").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            let variants: [(String, CatalystBadgeVariant)] = [
                ("Primary", .primary), ("Success", .success), ("Warning", .warning),
                ("Danger", .danger), ("Info", .info), ("Purple", .purple),
                ("Teal", .teal), ("Orange", .orange), ("Indigo", .indigo),
                ("Rose", .rose), ("Lime", .lime), ("Slate", .slate),
            ]
            FlowLayout(spacing: Catalyst.Spacing.space2) {
                ForEach(variants, id: \.0) { name, variant in CatalystBadge(label: name, variant: variant) }
            }
        }
    }
}

// MARK: - Autocomplete

private struct AutocompleteItem: Identifiable, CustomStringConvertible {
    let id: Int
    let name: String
    var description: String { name }
}

private struct AutocompleteSection: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selectedItem: String = "None"

    private let sampleItems: [AutocompleteItem] = [
        .init(id: 1, name: "Alice Johnson"),
        .init(id: 2, name: "Bob Williams"),
        .init(id: 3, name: "Charlie Brown"),
        .init(id: 4, name: "Diana Prince"),
        .init(id: 5, name: "Edward Norton"),
        .init(id: 6, name: "Fiona Apple"),
        .init(id: 7, name: "George Lucas"),
        .init(id: 8, name: "Hannah Montana"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Autocomplete").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            Text("Type a name to filter the dropdown. Mirrors the behavior of the CSS CatalystAutocomplete combobox.")
                .font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.secondary(scheme))

            CatalystFormGroup(label: "Search user") {
                CatalystAutocomplete(placeholder: "Type a name...", items: sampleItems) { item in
                    selectedItem = item.name
                }
            }
            .frame(maxWidth: 400)

            HStack(spacing: Catalyst.Spacing.space2) {
                Text("Selected:").font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.secondary(scheme))
                CatalystBadge(label: selectedItem, variant: .primary)
            }
        }
    }
}

// MARK: - Tables (simple)

private struct TablesSection: View {
    @Environment(\.colorScheme) private var scheme
    let data: [(String, String, String)] = [
        ("Alice", "alice@example.com", "Admin"),
        ("Bob", "bob@example.com", "Editor"),
        ("Charlie", "charlie@example.com", "Viewer"),
        ("Diana", "diana@example.com", "Admin"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Tables").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            VStack(spacing: 0) {
                CatalystTableHeader(columns: ["Name", "Email", "Role"])
                ForEach(data, id: \.0) { name, email, role in
                    CatalystTableRow {
                        Text(name).font(Catalyst.Typography.callout).frame(maxWidth: .infinity, alignment: .leading)
                        Text(email).font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.secondary(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CatalystBadge(label: role, variant: role == "Admin" ? .primary : role == "Editor" ? .teal : .slate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .catalystBorder(scheme)
        }
    }
}

// MARK: - Data Table (sortable, richer)

private struct Employee: Identifiable {
    let id: Int; let name: String; let department: String; let status: String; let hours: Int
}

private struct DataTableSection: View {
    @Environment(\.colorScheme) private var scheme
    private let employees: [Employee] = [
        .init(id: 1,  name: "Alice Johnson",   department: "Engineering", status: "Active",   hours: 42),
        .init(id: 2,  name: "Bob Williams",    department: "Design",      status: "Active",   hours: 38),
        .init(id: 3,  name: "Charlie Brown",   department: "Engineering", status: "On leave", hours: 0),
        .init(id: 4,  name: "Diana Prince",    department: "Marketing",   status: "Active",   hours: 40),
        .init(id: 5,  name: "Edward Norton",   department: "Engineering", status: "Active",   hours: 45),
        .init(id: 6,  name: "Fiona Apple",     department: "Design",      status: "Active",   hours: 36),
        .init(id: 7,  name: "George Lucas",    department: "Marketing",   status: "Inactive", hours: 0),
        .init(id: 8,  name: "Hannah Lee",      department: "Engineering", status: "Active",   hours: 41),
        .init(id: 9,  name: "Ivan Petrov",     department: "Design",      status: "Active",   hours: 39),
        .init(id: 10, name: "Julia Roberts",   department: "Marketing",   status: "Active",   hours: 37),
        .init(id: 11, name: "Kevin Hart",      department: "Engineering", status: "Active",   hours: 44),
        .init(id: 12, name: "Laura Chen",      department: "Design",      status: "On leave", hours: 0),
        .init(id: 13, name: "Mike Torres",     department: "Engineering", status: "Active",   hours: 43),
        .init(id: 14, name: "Nina Patel",      department: "Marketing",   status: "Active",   hours: 35),
        .init(id: 15, name: "Oscar Wilde",     department: "Design",      status: "Inactive", hours: 0),
        .init(id: 16, name: "Paula Santos",    department: "Engineering", status: "Active",   hours: 40),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Data Table").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            Text("Sortable columns, search, pagination, and entries-per-page selector. Mirrors the CSS DataTables integration.")
                .font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.secondary(scheme))

            CatalystDataTable(
                columns: [
                    .init("Name", id: "name"),
                    .init("Department", id: "dept"),
                    .init("Status", id: "status"),
                    .init("Hours", id: "hours"),
                ],
                rows: employees,
                searchableKeys: { "\($0.name) \($0.department) \($0.status)" }
            ) { row, col -> AnyView in
                switch col.id {
                case "name":
                    return AnyView(Text(row.name).font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.primary(scheme)))
                case "dept":
                    return AnyView(Text(row.department).font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.secondary(scheme)))
                case "status":
                    let variant: CatalystBadgeVariant = row.status == "Active" ? .success : row.status == "On leave" ? .warning : .slate
                    return AnyView(CatalystBadge(label: row.status, variant: variant))
                case "hours":
                    return AnyView(Text("\(row.hours)h").font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.primary(scheme)))
                default:
                    return AnyView(EmptyView())
                }
            }
        }
    }
}

// MARK: - Charts

private struct MonthlyData: Identifiable {
    let id: String
    let month: String
    let revenue: Double
    let expenses: Double
}

private struct ChartsSection: View {
    @Environment(\.colorScheme) private var scheme
    @State private var chartType = 0

    private let data: [MonthlyData] = [
        .init(id: "jan", month: "Jan", revenue: 42, expenses: 28),
        .init(id: "feb", month: "Feb", revenue: 38, expenses: 32),
        .init(id: "mar", month: "Mar", revenue: 55, expenses: 30),
        .init(id: "apr", month: "Apr", revenue: 48, expenses: 35),
        .init(id: "may", month: "May", revenue: 62, expenses: 38),
        .init(id: "jun", month: "Jun", revenue: 58, expenses: 40),
    ]

    private let categoryData: [(String, Double, Catalyst.AccentColor)] = [
        ("Engineering", 45, Catalyst.primary),
        ("Design", 25, Catalyst.teal),
        ("Marketing", 18, Catalyst.orange),
        ("Sales", 12, Catalyst.success),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Charts").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            Text("Native Swift Charts styled with Catalyst tokens. The chart-theme.js approach maps to using accent colors directly.")
                .font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.secondary(scheme))

            CatalystTabs(items: ["Bar", "Line", "Horizontal"], selected: $chartType)

            #if canImport(Charts)
            CatalystPanel(title: chartType == 0 ? "Revenue vs Expenses" : chartType == 1 ? "Revenue trend" : "Budget by department") {
                Group {
                    if chartType == 0 { barChart }
                    else if chartType == 1 { lineChart }
                    else { horizontalChart }
                }
                .frame(height: 240)
            }
            #else
            CatalystAlertBanner(.info, message: "Charts require iOS 16+ / macOS 13+ with the Charts framework.", title: "Charts unavailable")
            #endif

            SectionLabel("Legend")
            HStack(spacing: Catalyst.Spacing.lg) {
                LegendDot(label: "Revenue", color: Catalyst.primary.fill(scheme))
                LegendDot(label: "Expenses", color: Catalyst.danger.fill(scheme))
            }
        }
    }

    #if canImport(Charts)
    private var barChart: some View {
        Chart(data) { item in
            BarMark(x: .value("Month", item.month), y: .value("Revenue", item.revenue))
                .foregroundStyle(Catalyst.primary.fill(scheme))
                .cornerRadius(Catalyst.Radius.default)
            BarMark(x: .value("Month", item.month), y: .value("Expenses", item.expenses))
                .foregroundStyle(Catalyst.danger.fill(scheme))
                .cornerRadius(Catalyst.Radius.default)
        }
        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(Catalyst.Typography.caption1) } }
        .chartYAxis { AxisMarks { _ in AxisValueLabel().font(Catalyst.Typography.caption1); AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Catalyst.Border.primary(scheme)) } }
    }

    private var lineChart: some View {
        Chart(data) { item in
            LineMark(x: .value("Month", item.month), y: .value("Revenue", item.revenue))
                .foregroundStyle(Catalyst.primary.fill(scheme))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Month", item.month), y: .value("Revenue", item.revenue))
                .foregroundStyle(Catalyst.primary.fill(scheme))
            AreaMark(x: .value("Month", item.month), y: .value("Revenue", item.revenue))
                .foregroundStyle(Catalyst.primary.subtle(scheme).opacity(0.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(Catalyst.Typography.caption1) } }
        .chartYAxis { AxisMarks { _ in AxisValueLabel().font(Catalyst.Typography.caption1); AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Catalyst.Border.primary(scheme)) } }
    }

    private var horizontalChart: some View {
        Chart(categoryData, id: \.0) { name, value, accent in
            BarMark(x: .value("Budget", value), y: .value("Dept", name))
                .foregroundStyle(accent.fill(scheme))
                .cornerRadius(Catalyst.Radius.default)
        }
        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(Catalyst.Typography.caption1) } }
        .chartYAxis { AxisMarks { _ in AxisValueLabel().font(Catalyst.Typography.caption1) } }
    }
    #endif
}

private struct LegendDot: View {
    let label: String; let color: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: Catalyst.Spacing.space1) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(Catalyst.Typography.caption1).foregroundColor(Catalyst.Text.secondary(scheme))
        }
    }
}

// MARK: - Toasts & Alerts

private struct ToastsSection: View {
    let toastManager: CatalystToastManager
    @Environment(\.colorScheme) private var scheme
    @State private var showInfoAlert = true

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Toasts & Alerts").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            SectionLabel("Trigger toasts")
            HStack(spacing: Catalyst.Spacing.md) {
                CatalystButton("Success toast", role: .success) { toastManager.success("Changes saved.", title: "Done") }
                CatalystButton("Danger toast", role: .danger) { toastManager.danger("Request failed.") }
                CatalystButton("Warning toast", role: .warning) { toastManager.warning("Limit approaching.") }
                CatalystButton("Info toast") { toastManager.info("Update available.") }
            }
            SectionLabel("Inline alerts")
            VStack(spacing: Catalyst.Spacing.space2) {
                CatalystAlertBanner(.success, message: "All tests passed.", title: "Build complete")
                CatalystAlertBanner(.danger, message: "Validation failed.", title: "Error")
                CatalystAlertBanner(.warning, message: "Session expires in 5 minutes.")
                if showInfoAlert {
                    CatalystAlertBanner(.info, message: "This feature is in beta.", title: "Note", closable: true) {
                        withAnimation(Catalyst.Animation.normal) { showInfoAlert = false }
                    }
                }
            }
        }
    }
}

// MARK: - Dialogs (native sheet)

private struct DialogsSection: View {
    @ObservedObject var dialogManager: CatalystDialogManager
    @Environment(\.colorScheme) private var scheme
    @State private var showConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Dialogs").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            Text("Manager-based like toasts. Apply .catalystDialogs(manager) at the root. Present from anywhere via manager.present(...).")
                .font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.secondary(scheme))

            CatalystButton("Open dialog", role: .primary) {
                dialogManager.present("Confirm action") {
                    Text("Are you sure you want to proceed? This action cannot be undone.")
                        .font(Catalyst.Typography.body)
                } footer: {
                    CatalystButton("Cancel") { dialogManager.dismiss() }
                    CatalystButton("Confirm", role: .primary) {
                        dialogManager.dismiss()
                        withAnimation { showConfirmed = true }
                    }
                }
            }

            if showConfirmed {
                CatalystAlertBanner(.success, message: "Action was confirmed.", closable: true) {
                    withAnimation { showConfirmed = false }
                }
            }
        }
    }
}

// MARK: - Panels & Grids

private struct PanelsSection: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab = 0
    @State private var progress = 0.65

    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Panels & Grids").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            SectionLabel("Tabs")
            CatalystTabs(items: ["General", "Advanced", "Plugins"], selected: $selectedTab)
            Text("Selected tab index: \(selectedTab)")
                .font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.secondary(scheme))
            SectionLabel("Breadcrumbs")
            CatalystBreadcrumbs(items: [
                (label: "Home", id: "home"), (label: "Settings", id: "settings"), (label: "Account", id: nil),
            ])
            SectionLabel("Progress")
            CatalystProgressBar(value: progress)
            Slider(value: $progress, in: 0...1)
            SectionLabel("Accordion")
            VStack(spacing: -1) {
                CatalystAccordion("General settings") {
                    Text("Content for general settings goes here.")
                        .font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.primary(scheme))
                }
                CatalystAccordion("Advanced options") {
                    Text("Content for advanced options goes here.")
                        .font(Catalyst.Typography.body).foregroundColor(Catalyst.Text.primary(scheme))
                }
            }
            SectionLabel("Grid (2-column)")
            CatalystGrid(columns: 2) {
                ForEach(1...4, id: \.self) { i in
                    CatalystPanel(title: "Card \(i)") {
                        Text("Panel content").font(Catalyst.Typography.callout).foregroundColor(Catalyst.Text.secondary(scheme))
                    }
                }
            }
        }
    }
}

// MARK: - Typography

private struct TypographySection: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Typography").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            Group {
                TypeRow("Large Title — 32pt bold", font: Catalyst.Typography.largeTitle)
                TypeRow("Title 1 — 26pt bold", font: Catalyst.Typography.title1)
                TypeRow("Title 2 — 21pt semibold", font: Catalyst.Typography.title2)
                TypeRow("Title 3 — 19pt semibold", font: Catalyst.Typography.title3)
                TypeRow("Headline — 16pt semibold", font: Catalyst.Typography.headline)
                TypeRow("Body — 16pt regular", font: Catalyst.Typography.body)
                TypeRow("Callout — 15pt regular", font: Catalyst.Typography.callout)
                TypeRow("Subheadline — 14pt regular", font: Catalyst.Typography.subheadline)
                TypeRow("Footnote — 13pt regular", font: Catalyst.Typography.footnote)
                TypeRow("Caption 1 — 12pt", font: Catalyst.Typography.caption1)
            }
            TypeRow("Caption 2 — 11pt", font: Catalyst.Typography.caption2)
            Text("Monospaced: let x = 42").font(Catalyst.Typography.mono).foregroundColor(Catalyst.Text.primary(scheme))
        }
    }
}

private struct TypeRow: View {
    let label: String; let font: Font
    @Environment(\.colorScheme) private var scheme
    init(_ label: String, font: Font) { self.label = label; self.font = font }
    var body: some View {
        Text(label).font(font).foregroundColor(Catalyst.Text.primary(scheme)).padding(.vertical, 2)
    }
}

// MARK: - Colors

private struct ColorsSection: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
            Text("Color Palette").font(Catalyst.Typography.largeTitle).foregroundColor(Catalyst.Text.primary(scheme))
            SectionLabel("Surfaces")
            HStack(spacing: Catalyst.Spacing.space2) {
                ColorSwatch("bg", color: Catalyst.Surface.bg(scheme))
                ColorSwatch("surface", color: Catalyst.Surface.surface(scheme))
                ColorSwatch("raised", color: Catalyst.Surface.raised(scheme))
            }
            SectionLabel("12 Semantic Accents")
            CatalystAdaptiveGrid(minWidth: 200) {
                ForEach(Catalyst.allAccents, id: \.name) { name, color in
                    AccentCard(name: name, accent: color)
                }
            }
        }
    }
}

private struct ColorSwatch: View {
    let name: String; let color: Color
    @Environment(\.colorScheme) private var scheme
    init(_ name: String, color: Color) { self.name = name; self.color = color }
    var body: some View {
        VStack(spacing: Catalyst.Spacing.space1) {
            RoundedRectangle(cornerRadius: Catalyst.Radius.default).fill(color)
                .frame(width: 64, height: 40)
                .overlay(RoundedRectangle(cornerRadius: Catalyst.Radius.default).stroke(Catalyst.Border.primary(scheme), lineWidth: 1))
            Text(name).font(Catalyst.Typography.caption2).foregroundColor(Catalyst.Text.secondary(scheme))
        }
    }
}

private struct AccentCard: View {
    let name: String; let accent: Catalyst.AccentColor
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Catalyst.Spacing.space2) {
            HStack(spacing: Catalyst.Spacing.space2) {
                RoundedRectangle(cornerRadius: Catalyst.Radius.default).fill(accent.fill(scheme)).frame(width: 32, height: 32)
                RoundedRectangle(cornerRadius: Catalyst.Radius.default).fill(accent.hover(scheme)).frame(width: 32, height: 32)
                RoundedRectangle(cornerRadius: Catalyst.Radius.default).fill(accent.subtle(scheme)).frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: Catalyst.Radius.default).stroke(Catalyst.Border.primary(scheme), lineWidth: 1))
            }
            HStack(spacing: Catalyst.Spacing.space2) {
                Text(name).font(Catalyst.Typography.caption1).fontWeight(.semibold).foregroundColor(accent.text(scheme))
                Spacer()
                Text("text").font(Catalyst.Typography.caption2).foregroundColor(accent.text(scheme))
            }
        }
        .padding(Catalyst.Spacing.space3)
        .background(Catalyst.Surface.bg(scheme))
        .catalystBorder(scheme)
    }
}

// MARK: - Helpers

private struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Catalyst.Typography.headline).foregroundColor(Catalyst.Text.primary(scheme))
            .padding(.top, Catalyst.Spacing.space2)
    }
}

// MARK: - FlowLayout (with cache)

private struct FlowLayout: Layout {
    let spacing: CGFloat

    struct RowCache {
        var rows: [[Int]] = []
    }

    func makeCache(subviews: Subviews) -> RowCache { RowCache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout RowCache) -> CGSize {
        cache.rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in cache.rows.enumerated() {
            let rowH = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowH + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout RowCache) {
        var y = bounds.minY
        for row in cache.rows {
            let rowH = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for idx in row {
                let size = subviews[idx].sizeThatFits(.unspecified)
                subviews[idx].place(at: CGPoint(x: x, y: y), proposal: .init(size))
                x += size.width + spacing
            }
            y += rowH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        let maxW = proposal.width ?? .infinity
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if x + size.width > maxW && !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(i)
            x += size.width + spacing
        }
        return rows
    }
}

// MARK: - Previews

#Preview("Catalyst Showcase") { CatalystShowcaseView() }
#Preview("Catalyst Showcase — Dark") { CatalystShowcaseView().preferredColorScheme(.dark) }
