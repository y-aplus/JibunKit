import ProjectDescription

let name: Template.Attribute = .required("name")
let template = Template(
    description: "Independent Swift Package Feature with a standalone app shell",
    attributes: [name],
    items: [
        .file(path: "Modules/\(name)/Package.swift", templatePath: "Package.stencil"),
        .file(path: "Modules/\(name)/Project.swift", templatePath: "Project.stencil"),
        .file(path: "Modules/\(name)/Sources/\(name)Feature/\(name)RootView.swift", templatePath: "View.stencil"),
        .file(path: "Modules/\(name)/Example/App.swift", templatePath: "App.stencil"),
    ]
)
