# Data flow

lua-objc has no `Binding`, `@State`, `@Observable`, or `onChange(of:)` modifier.

- Models own domain data and never import AppKit, UIKit, or `ns`.
- A controller action resolves input, calls the model, then updates retained refs or renders again. Do not put the save inside a hand-rolled binding getter.
- Template callbacks arrive as `data.actions`. Bind them with the `action` attribute. Do not close over widget refs inside the template.
- Pass stable record ids into actions. Resolve and validate them in the model.
- Do not decorate shared model records with presentation fields. Format in the template or in a small view-data table.
- Structural changes go through the retained template. Do not mutate a native subtree from an app to simulate observation. That boundary is `docs/retained-templates.md`.
- Query the controller's model instance. Do not reach into a module-level catalog from a view.
