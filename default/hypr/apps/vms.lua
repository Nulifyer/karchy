-- The Virtual machines window is a shell window (Quickshell's class), so match
-- its title, as for karchy Settings. It sizes itself to fit the screen.
o.window({ class = "^org.quickshell$", title = "^Virtual machines$" }, { float = true })
o.window({ class = "^org.quickshell$", title = "^Virtual machines$" }, { center = true })

-- The Containers window, the same way.
o.window({ class = "^org.quickshell$", title = "^Containers$" }, { float = true })
o.window({ class = "^org.quickshell$", title = "^Containers$" }, { center = true })
