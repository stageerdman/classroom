import "@blocknote/core/fonts/inter.css";
import { BlockNoteView } from "@blocknote/mantine";
import "@blocknote/mantine/style.css";
import { useCreateBlockNote } from "@blocknote/react";

// Spike only: no load/save, no timenotes, no bridge to Swift — just
// BlockNote's default editor mounted full-window, to evaluate the
// editing feel and whether embedding it in a WKWebView is tractable.
// See updates/2026-09-02 BLOCKNOTE-SPIKE - OPEN/update.md.
export default function App() {
  const editor = useCreateBlockNote({
    initialContent: [
      {
        type: "heading",
        content: "BlockNote spike"
      },
      {
        type: "paragraph",
        content: "This is a throwaway evaluation window — nothing here saves or loads real lesson data yet. Try typing, the slash menu (/), and selecting text to see the formatting toolbar."
      }
    ]
  });

  return (
    <div style={{ padding: "24px 48px", height: "100vh", boxSizing: "border-box" }}>
      <BlockNoteView editor={editor} />
    </div>
  );
}
