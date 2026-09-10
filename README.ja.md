<p align="center">
  <img src="packaging/Assets/SmartZip.png" width="112" alt="SmartZip logo">
</p>
<h1 align="center">SmartZip</h1>
<p align="center">Windows 11 の新しい右クリックメニューから解凍。</p>
<p align="center">
  <img src="https://img.shields.io/badge/Windows_11-x64-0078D4?style=flat-square" alt="Windows 11 x64">
  <a href="https://github.com/yueyangcode/SmartZip/releases/tag/v0.1.0.15-test"><img src="https://img.shields.io/badge/0.1.0.15-preview-F59E0B?style=flat-square" alt="0.1.0.15 public preview"></a>
  <a href="docs/BUILD-0.1.0.15.md"><img src="https://img.shields.io/badge/Installer-14.45_MiB-6366F1?style=flat-square" alt="Installer: 14.45 MiB"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Source_license-MIT-22C55E?style=flat-square" alt="Project source: MIT license"></a>
</p>
<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.zh-TW.md">繁體中文</a> · <strong>日本語</strong>
</p>

## 特長

- **最初のメニューから解凍**：圧縮ファイルを選び、**智能解压** をクリック。「その他のオプションを確認」は不要です。
- **解凍エンジンを同梱**：7-Zip や WinRAR を別途インストールする必要はなく、既存の圧縮ソフトとも併用できます。
- **主要形式と複数選択に対応**：ZIP、RAR、7Z、CAB、TAR、GZ、GZIP、BZ2 と対応する番号付き分割ファイル。中国語の文字、空白、特殊文字を含むパスも扱えます。

## 入手と使い方

**`0.1.0.15` プレビュー版を公開しました。自己署名のテスト証明書を使用する開発版で、安定版ではありません。** [ダウンロードとインストール手順](https://github.com/yueyangcode/SmartZip/releases/tag/v0.1.0.15-test) · [公開状況](docs/RELEASE.md)

対応環境は **Windows 11 x64、Build 22621 以降**です。テスト用インストーラーを入手したら：

1. SHA-256 を照合し、`SmartZipSetup-0.1.0.15-test.exe` を実行します。
2. 親フォルダーを選択すると、`SmartZip` フォルダーを追加して現在のユーザー用にインストールします。
3. 圧縮ファイルを右クリック → **智能解压**。設定と通常のアンインストーラーは、スタートメニューの SmartZip フォルダーにあります。

> **テスト証明書：** 初回インストールでは、同意後に証明書ヘルパーが管理者権限を要求し、公開鍵証明書のみを `LocalMachine\TrustedPeople` に追加します。Root への追加や秘密鍵のインポートは行いません。削除時は証明書の所有権を確認し、インストール前から存在した証明書を引き継ぎません。Windows のセキュリティ保護を無効にしないでください。

## 更新と制限

- 正常な旧テスト版からは、同じフォルダー・同じ証明書で更新できます。登録情報の不整合やアンインストールの失敗時はログを保存して報告し、強制削除しないでください。
- 公開 WinGet パッケージはありません。更新機能は下書きとプレリリースを対象外とするため、このテスト版の公開で更新通知は表示されません。
- `.15` への更新は配置ログを検証済みです。新アイコンと ZIP の解凍はユーザーが確認しました。通常の UAC 有効環境とリモート更新の一連の動作は未検証です。[検証の詳細](docs/SANDBOX-0.1.0.15-ACCEPTANCE.md)
- README の翻訳はアプリの多言語化を意味しません。現在のインストーラーとメニューは簡体字中国語です。

## 開発とライセンス

Windows、PowerShell 7.4+、.NET SDK 8.0.425 でビルドします。主な使用言語は C++、C#、AutoHotkey です。

```powershell
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.15
```

[ビルド手順](docs/BUILD-0.1.0.15.md) · [更新機能の設計](docs/UPDATER.md) · [問題を報告](https://github.com/yueyangcode/SmartZip/issues)

本プロジェクトのソースは [MIT](LICENSE) ライセンスです。同梱コンポーネントには別のライセンスとソース提供条件があります。[サードパーティー通知](ThirdPartyNotices.md)をご確認ください。[vvyoko/SmartZip](https://github.com/vvyoko/SmartZip) を基にした独立した統合プロジェクトです。
