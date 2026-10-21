import ChurchTVEditors

// The Create section lives in the ChurchTVEditors package (apple/ChurchTVEditors, Sources/.../Create/CreateView.swift) so the Mac app
// can use it too. These aliases keep the names `CreateRoot` / `CreateView` working everywhere in the Remote target (RootView etc.).
typealias CreateRoot = ChurchTVEditors.CreateRoot
typealias CreateView = ChurchTVEditors.CreateView
