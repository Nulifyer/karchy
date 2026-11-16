pragma Singleton
import QtQuick

// Whether the person is driving the shell with the keyboard or the pointer
// right now. The panels and the menu move one cursor with both, so the cursor
// alone can't say whether to draw the focus ring: FocusRing shows it only
// while `keyboard` is true, so a row under the pointer gets the hover look and
// a row reached with j/k gets the ring.
//
// PanelKeyCatcher, the menu and ConfirmDialog call keyPressed() on every key;
// PanelKeyCatcher and PointerMoveGate call pointerMoved() when the pointer
// really moves (not when a list scrolls under a still pointer).
//
// Qt focus in windows (Settings, Containers, VMs) doesn't need this: there
// FocusRing reads the focus reason, so a click focuses without a ring and Tab
// shows it.
QtObject {
  property bool keyboard: true

  function keyPressed() { keyboard = true }
  function pointerMoved() { keyboard = false }
}
