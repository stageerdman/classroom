import "@blocknote/core/fonts/inter.css";
import { filterSuggestionItems } from "@blocknote/core";
import { BlockNoteView } from "@blocknote/mantine";
import "@blocknote/mantine/style.css";
import {
  getDefaultReactSlashMenuItems,
  SuggestionMenuController,
  useCreateBlockNote
} from "@blocknote/react";
import { useEffect, useRef, useState } from "react";
import { postToSwift } from "./bridge";
import { formatTimestamp, parseTimenoteHref, timenoteHref } from "./timenote";

// The interface Swift's BlockNoteEditorView.Coordinator calls into via
// `webView.evaluateJavaScript`. See bridge.ts for the JS -> Swift
// direction.
export interface ClassroomBridge {
  loadMarkdown: (markdown: string, editable: boolean) => Promise<void>;
  setEditable: (editable: boolean) => void;
  insertTimenoteAtEnd: (seconds: number) => Promise<void>;
  setCurrentPlaybackSeconds: (seconds: number) => void;
}

declare global {
  interface Window {
    classroomBridge?: ClassroomBridge;
  }
}

const CONTENT_CHANGE_DEBOUNCE_MS = 400;

export default function App() {
  const editor = useCreateBlockNote({
    initialContent: [{ type: "paragraph", content: "" }]
  });
  const [editable, setEditable] = useState(true);

  // Guards against feeding our own `onChange` notification back into
  // `loadMarkdown` as if it were an externally-driven content change —
  // that would fight the user's typing with a full reparse-and-replace
  // on every keystroke.
  const isApplyingExternalUpdateRef = useRef(false);
  const currentPlaybackSecondsRef = useRef(0);
  const debounceTimerRef = useRef<number | undefined>(undefined);

  const insertTimenoteAtCursor = (seconds: number) => {
    editor.insertInlineContent([
      { type: "link", href: timenoteHref(seconds), content: formatTimestamp(seconds) },
      " "
    ]);
  };

  useEffect(() => {
    const bridge: ClassroomBridge = {
      loadMarkdown: async (markdown, isEditable) => {
        isApplyingExternalUpdateRef.current = true;
        try {
          const parsed = await editor.tryParseMarkdownToBlocks(markdown.length > 0 ? markdown : " ");
          editor.replaceBlocks(editor.document, parsed.length > 0 ? parsed : [{ type: "paragraph", content: "" }]);
          setEditable(isEditable);
        } finally {
          isApplyingExternalUpdateRef.current = false;
        }
      },
      setEditable: (isEditable) => setEditable(isEditable),
      insertTimenoteAtEnd: async (seconds) => {
        const blocks = editor.document;
        const lastBlock = blocks[blocks.length - 1];
        const [insertedBlock] = editor.insertBlocks([{ type: "paragraph", content: "" }], lastBlock, "after");
        editor.setTextCursorPosition(insertedBlock, "end");
        insertTimenoteAtCursor(seconds);
        editor.focus();
      },
      setCurrentPlaybackSeconds: (seconds) => {
        currentPlaybackSecondsRef.current = seconds;
      }
    };
    window.classroomBridge = bridge;
    postToSwift({ type: "ready" });

    // BlockNote renders a timenote as a plain markdown link (see
    // insertTimenoteAtCursor) so it round-trips through
    // blocksToMarkdownLossy/tryParseMarkdownToBlocks with zero special
    // casing. Clicking it inside a contentEditable region doesn't
    // navigate by default, so this intercepts it and asks Swift to seek
    // instead, rather than relying on BlockNote's own link-click
    // handling (which would try to open it as a real URL).
    const handleClick = (event: MouseEvent) => {
      const anchor = (event.target as HTMLElement | null)?.closest("a");
      const href = anchor?.getAttribute("href");
      const seconds = href ? parseTimenoteHref(href) : null;
      if (seconds === null) {
        return;
      }
      event.preventDefault();
      postToSwift({ type: "timenoteClicked", seconds });
    };
    document.addEventListener("click", handleClick, true);

    return () => {
      document.removeEventListener("click", handleClick, true);
      delete window.classroomBridge;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleChange = () => {
    if (isApplyingExternalUpdateRef.current) {
      return;
    }
    window.clearTimeout(debounceTimerRef.current);
    debounceTimerRef.current = window.setTimeout(async () => {
      const markdown = await editor.blocksToMarkdownLossy();
      postToSwift({ type: "contentChanged", markdown });
    }, CONTENT_CHANGE_DEBOUNCE_MS);
  };

  return (
    <BlockNoteView editor={editor} editable={editable} onChange={handleChange} slashMenu={false}>
      <SuggestionMenuController
        triggerCharacter="/"
        getItems={async (query) =>
          filterSuggestionItems(
            [
              ...getDefaultReactSlashMenuItems(editor),
              {
                title: "Timenote",
                subtext: "Link a note to the current playback position",
                aliases: ["timenote", "timestamp"],
                group: "Media",
                onItemClick: () => insertTimenoteAtCursor(currentPlaybackSecondsRef.current)
              }
            ],
            query
          )
        }
      />
    </BlockNoteView>
  );
}
