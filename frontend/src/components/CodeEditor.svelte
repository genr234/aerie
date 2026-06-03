<script lang="ts">
  import { createEventDispatcher, onDestroy, onMount } from "svelte";
  import * as monaco from "monaco-editor";
  import editorWorker from "monaco-editor/esm/vs/editor/editor.worker?worker";
  import jsonWorker from "monaco-editor/esm/vs/language/json/json.worker?worker";
  import type { Diagnostic } from "../lib/types";

  export let value = "";
  export let path = "";
  export let diagnostics: Diagnostic[] = [];
  export let readOnly = false;

  const dispatch = createEventDispatcher<{ change: string; save: void }>();
  let host: HTMLDivElement;
  let editor: monaco.editor.IStandaloneCodeEditor | undefined;
  let model: monaco.editor.ITextModel | undefined;
  let suppress = false;

  const wrenApi = [
    ["Events.message", 'Events.message("$1", ${2:2})'],
    ["State.set", 'State.set("$1", ${2:true})'],
    ["State.getFlag", 'State.getFlag("$1")'],
    ["State.update", 'State.update("$1", Fn.new {|value| $2 })'],
    ["Scene.go", 'Scene.go("$1")'],
    ["Scene.findIndex", 'Scene.findIndex("$1")'],
    ["Scene.currentIndex", "Scene.currentIndex()"],
    ["UI.text", 'UI.text(${1:18}, ${2:18}, "$3")'],
  ] as const;

  onMount(() => {
    installMonacoEnvironment();
    registerWrenLanguage();
    openModel();
    editor = monaco.editor.create(host, {
      model,
      automaticLayout: true,
      fontSize: 13,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      tabSize: 2,
      insertSpaces: true,
      readOnly,
      wordWrap: "on",
      renderWhitespace: "selection",
      fixedOverflowWidgets: true,
    });
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () =>
      dispatch("save"),
    );
    editor.onDidChangeModelContent(() => {
      if (suppress || !model) return;
      dispatch("change", model.getValue());
    });
    applyMarkers();
  });

  $: if (model && value !== model.getValue()) {
    suppress = true;
    model.setValue(value);
    suppress = false;
  }

  $: if (editor) editor.updateOptions({ readOnly });

  $: if (editor && model && path && model.uri.path !== `/${path}`) {
    openModel();
    editor.setModel(model ?? null);
    applyMarkers();
  }

  $: if (model) applyMarkers();

  onDestroy(() => {
    editor?.dispose();
    model?.dispose();
  });

  function installMonacoEnvironment() {
    const globalWindow = window as typeof window & {
      MonacoEnvironment?: monaco.Environment;
    };
    globalWindow.MonacoEnvironment ??= {
      getWorker(_workerId: string, label: string) {
        return label === "json" ? new jsonWorker() : new editorWorker();
      },
    };
  }

  function registerWrenLanguage() {
    if (
      monaco.languages
        .getLanguages()
        .some(
          (language: monaco.languages.ILanguageExtensionPoint) =>
            language.id === "wren",
        )
    )
      return;
    monaco.languages.register({ id: "wren", extensions: [".wren"] });
    monaco.languages.setMonarchTokensProvider("wren", {
      keywords: [
        "class",
        "static",
        "var",
        "if",
        "else",
        "for",
        "while",
        "return",
        "import",
        "for",
        "in",
        "true",
        "false",
        "null",
        "Fn",
        "new",
      ],
      tokenizer: {
        root: [
          [/\/\/.*$/, "comment"],
          [/"([^"\\]|\\.)*$/, "string.invalid"],
          [/"/, "string", "@string"],
          [/[{}()[\]]/, "@brackets"],
          [
            /[a-zA-Z_]\w*/,
            { cases: { "@keywords": "keyword", "@default": "identifier" } },
          ],
          [/\d+(\.\d+)?/, "number"],
        ],
        string: [
          [/[^\\"]+/, "string"],
          [/\\./, "string.escape"],
          [/"/, "string", "@pop"],
        ],
      },
    });
    monaco.languages.registerCompletionItemProvider("wren", {
      triggerCharacters: [".", '"'],
      provideCompletionItems() {
        return {
          suggestions: wrenApi.map(([label, insertText]) => ({
            label,
            kind: monaco.languages.CompletionItemKind.Function,
            insertText,
            insertTextRules:
              monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
            range: undefined as unknown as monaco.IRange,
          })),
        };
      },
    });
  }

  function openModel() {
    const uri = monaco.Uri.parse(`file:///${path || "untitled.txt"}`);
    const existing = monaco.editor.getModel(uri);
    model =
      existing ?? monaco.editor.createModel(value, languageForPath(path), uri);
    if (existing && existing.getValue() !== value) existing.setValue(value);
  }

  function applyMarkers() {
    if (!model) return;
    const markers = diagnostics
      .filter((diagnostic) => diagnostic.path === path)
      .map((diagnostic) => {
        const line = diagnostic.line ?? 1;
        const column = diagnostic.column ?? 1;
        return {
          severity:
            diagnostic.severity === "error"
              ? monaco.MarkerSeverity.Error
              : diagnostic.severity === "warning"
                ? monaco.MarkerSeverity.Warning
                : monaco.MarkerSeverity.Info,
          message: diagnostic.message,
          startLineNumber: line,
          startColumn: column,
          endLineNumber: line,
          endColumn: column + 1,
        };
      });
    monaco.editor.setModelMarkers(model, "game-engine", markers);
  }

  function languageForPath(filePath: string): string {
    if (filePath.endsWith(".json")) return "json";
    if (filePath.endsWith(".wren")) return "wren";
    return "plaintext";
  }
</script>

<div class="code-editor" bind:this={host}></div>
