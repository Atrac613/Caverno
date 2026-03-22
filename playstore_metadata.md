# Caverno — Google Play Store Metadata

## App Title (max 50 chars)

- **EN:** Caverno - Local AI Chat with Tools
- **JA:** Caverno - ローカルAIチャット＆ツール

---

## Short Description (max 80 chars)

- **EN:** Chat with local LLMs (Ollama, LM Studio) using voice, tools, and memory.
- **JA:** ローカルLLM（Ollama, LM Studio）と音声・ツール・メモリでチャット。

---

## Full Description (max 4000 chars)

### English

Caverno is a powerful chat client for locally-hosted LLMs. Connect to Ollama, LM Studio, vLLM, or any OpenAI-compatible API endpoint and start chatting — no cloud required.

KEY FEATURES

• Any OpenAI-Compatible Server
Connect to your own LLM running on localhost or your local network. Supports any endpoint that speaks the OpenAI API format.

• Tool Calling (MCP Protocol)
Extend your AI with real-time tools — web search, calculator, code execution, and more. Caverno uses the Model Context Protocol to let your LLM take actions.

• Session Memory
Your assistant remembers your preferences, constraints, and context across conversations. Memory is stored locally and fully under your control.

• Voice In & Out
Speak your messages and have responses read aloud. Configurable speech rate and auto-read options.

• Image Attachments
Attach photos from your library to include visual context in your conversations.

• Multiple Conversations
Create, switch, and manage separate chat threads. All conversations are persisted locally.

• Assistant Modes
Switch between General and Coding modes for different response styles tailored to your task.

• Settings Import/Export
Share your configuration via JSON file or QR code. Easily transfer settings between devices with built-in validation.

• Background Notifications
Receive local notifications when AI responses arrive while the app is in the background.

• Bilingual UI
Full English and Japanese interface — switch languages instantly in settings.

• Privacy First
No account required. No data sent to third parties. All conversations and memory stay on your device — the only network connection is to the server you configure.

GETTING STARTED
1. Install an OpenAI-compatible LLM server (Ollama, LM Studio, etc.)
2. Open Caverno and go to Settings
3. Enter your server URL and select a model
4. Start chatting!

Caverno is designed for developers, AI enthusiasts, and anyone who wants full control over their AI assistant.

### Japanese

Cavernoは、ローカルで動くLLMのためのチャットクライアントです。Ollama、LM Studio、vLLMなど、OpenAI互換APIに対応。クラウド不要で、あなたのサーバーに直接接続します。

主な機能

• OpenAI互換サーバー対応
ローカルホストやネットワーク上のLLMに接続。OpenAI APIフォーマットに対応するすべてのエンドポイントで動作します。

• ツール呼び出し（MCPプロトコル）
Web検索、計算機、コード実行などのツールでAIを拡張。Model Context Protocolにより、LLMがリアルタイムにアクションを実行します。

• セッションメモリ
あなたの好みや制約をセッションをまたいで記憶。メモリはローカルに保存され、完全にあなたの管理下にあります。

• 音声入出力
音声でメッセージを送信し、応答を読み上げ。速度やオート読み上げの設定も可能です。

• 画像添付
写真ライブラリから画像を添付して、視覚的なコンテキストを会話に含められます。

• 複数会話管理
複数のチャットスレッドを作成・切替・管理。すべての会話はローカルに保存されます。

• アシスタントモード
汎用モードとコーディングモードを切り替えて、タスクに合った応答スタイルを選べます。

• 設定のインポート/エクスポート
JSONファイルやQRコードで設定を共有。バリデーション付きで安全にデバイス間の設定移行ができます。

• バックグラウンド通知
アプリがバックグラウンド時にAIの応答をローカル通知で受け取れます。

• 日英バイリンガルUI
日本語・英語のインターフェースを設定から即座に切り替え可能。

• プライバシー重視
アカウント不要。第三者へのデータ送信なし。すべての会話とメモリは端末に残ります。接続先はあなたが設定したサーバーだけです。

使い方
1. OpenAI互換LLMサーバー（Ollama、LM Studioなど）をインストール
2. Cavernoを開き、設定画面へ
3. サーバーURLを入力し、モデルを選択
4. チャット開始！

Cavernoは開発者、AI愛好家、そしてAIアシスタントを自分でコントロールしたいすべての人のためのアプリです。

---

## Data Safety Notes (for Console entry)

- **Data encryption**: All data stored locally (Hive/SharedPreferences). No data in transit to developer servers.
- **Data collection**: No personal data collected. No account info.
- **Third-party sharing**: No data shared with third parties.
- **Permissions**:
    - Internet: To connect to user-provided API endpoints.
    - Microphone/Speech: For Voice Mode (STT/TTS).
    - Camera: For scanning settings QR codes and image attachments.
    - Wake Lock: To keep connection alive during streaming responses.
