// JS -> Swift messages, posted through the WKScriptMessageHandler
// registered as "classroomBridge" in BlockNoteEditorView.swift. The
// Swift -> JS direction is the mirror: Swift calls functions Swift
// attaches to `window.classroomBridge` directly via `evaluateJavaScript`
// (see App.tsx's effect that assigns `window.classroomBridge`).
export type BridgeMessage =
  | { type: "ready" }
  | { type: "contentChanged"; markdown: string }
  | { type: "timenoteClicked"; seconds: number };

interface WebkitMessageHandlers {
  webkit?: {
    messageHandlers?: {
      classroomBridge?: {
        postMessage: (message: BridgeMessage) => void;
      };
    };
  };
}

export function postToSwift(message: BridgeMessage): void {
  (window as unknown as WebkitMessageHandlers).webkit?.messageHandlers?.classroomBridge?.postMessage(message);
}
