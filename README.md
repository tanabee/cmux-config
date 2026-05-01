# cmux config

[cmux](https://github.com/manaflow-ai/cmux) と、cmux の内蔵ターミナルが利用する [Ghostty](https://ghostty.org/) の個人設定一式です。`config/` 以下を `~/.config/` に置くと cmux 関連の設定が有効になります。

## 前提: cmux 本体と CLI (`bin/cmux`) のインストール

- `/Applications/cmux.app` が必要です。[manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) のリリースから dmg を取得するか、利用しているパッケージマネージャ (Homebrew Cask 等) で導入してください。
- cmux CLI は app バンドル内に同梱されており、`/Applications/cmux.app/Contents/Resources/bin/cmux` に存在します。
- `scripts/ghostty-opacity.sh` はこの絶対パスを直接呼ぶので、CLI を PATH に通さなくても動作します。
- ターミナルから素の `cmux` コマンドを使いたい場合だけ、シンボリックリンクで PATH に通します:

```sh
# Intel Mac / Homebrew (/usr/local) を使っている場合
sudo ln -sf /Applications/cmux.app/Contents/Resources/bin/cmux /usr/local/bin/cmux

# Apple Silicon の Homebrew prefix を使っている場合
sudo ln -sf /Applications/cmux.app/Contents/Resources/bin/cmux /opt/homebrew/bin/cmux
```

または `~/.zshrc` 等で PATH に追加:

```sh
export PATH="/Applications/cmux.app/Contents/Resources/bin:$PATH"
```

cmux 本体をアップデートしても app バンドル内のパスは変わらないので、symlink / PATH 設定はそのまま使えます。

## 構成

```
config/
├── cmux/
│   ├── settings.json              # cmux 本体の設定 (JSONC)
│   └── scripts/
│       └── ghostty-opacity.sh     # ghostty の background-opacity を増減
└── ghostty/
    ├── config                     # ghostty 設定 (cmux 内蔵ターミナルが参照)
    └── passthrough.glsl           # custom-shader (パススルー)
```

- `~/.config/cmux/settings.json` は Application Support 側の設定より優先されます。
- `cmux/settings.json` は JSONC 形式で、コメントアウトを外したキーだけがファイル管理対象になります。

## セットアップ

シンボリックリンクで `~/.config/` に配置します。

```sh
mkdir -p ~/.config
ln -s "$PWD/config/cmux"    ~/.config/cmux
ln -s "$PWD/config/ghostty" ~/.config/ghostty
```

既存ファイルがある場合は上書きされないので、必要に応じて退避してください。

## scripts/ghostty-opacity.sh

cmux 内蔵ターミナルの背景不透明度をキーバインドから増減するためのヘルパーです。キーバインド自体は [Karabiner Elements](https://karabiner-elements.pqrs.org/) の Complex Modifications でこのスクリプトを呼ぶように設定しています (Karabiner の設定はこのリポジトリには含めていません)。

```sh
# 単発で増減
~/.config/cmux/scripts/ghostty-opacity.sh +        # +0.05
~/.config/cmux/scripts/ghostty-opacity.sh - 0.10   # -0.10

# 長押し対応 (キー押下/離し をフックする用途)
~/.config/cmux/scripts/ghostty-opacity.sh hold +   # 押下時: 即時 +0.05 → 連続変更ループ開始
~/.config/cmux/scripts/ghostty-opacity.sh release  # 離した時: ループ停止
```

`~/.config/ghostty/config` の `background-opacity` を書き換えたうえで、`/Applications/cmux.app` の `cmux reload-config` と `cmux refresh-surfaces` を並列で呼び出して即時反映します。範囲は 0.10〜1.00。

`hold` モードは「ticker と applier を分離する coalescing 設計」になっています:

- **ticker** (`TICK_INTERVAL=0.02s` ごと): `/tmp/cmux-opacity.target` に目標 opacity を書き込むだけ。cmux は呼ばない。
- **applier**: 最新 target を読み、前回適用値と異なれば config を書き換えて `cmux reload-config` / `refresh-surfaces` を呼び出す。cmux 待ちの間に target がさらに進むので、applier は中間値をスキップして最新値にジャンプする (= coalesce)。

これにより、cmux CLI の処理時間に律速されずに長押しスイープが滑らかに進むようになっています。lockfile は `/tmp/cmux-opacity.hold` で、ticker・applier の PID を記録します。`release` で lockfile を消して両プロセスを kill。

### Karabiner Elements 設定

cmux アプリが最前面のときだけ `⌘⇧+` / `⌘⇧-` で透過度を増減し、長押しで連続変更させる設定例です。`~/.config/karabiner/karabiner.json` の `profiles[].complex_modifications.rules` に以下の rule を追加 (もしくは Karabiner-Elements の Preferences → Complex Modifications → Add rule から JSON を import) してください。

```jsonc
{
  "description": "cmux 起動中: ⌘⇧+ / ⌘⇧- でターミナル透過度を増減 (0.02 刻み, 長押しで連続変更)",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        "key_code": "equal_sign",
        "modifiers": { "mandatory": ["command", "shift"], "optional": ["caps_lock"] }
      },
      "to": [
        { "shell_command": "$HOME/.config/cmux/scripts/ghostty-opacity.sh hold + 0.02" }
      ],
      "to_after_key_up": [
        { "shell_command": "$HOME/.config/cmux/scripts/ghostty-opacity.sh release" }
      ],
      "conditions": [
        { "type": "frontmost_application_if", "bundle_identifiers": ["^com\\.cmuxterm\\.app$"] }
      ]
    },
    {
      "type": "basic",
      "from": {
        "key_code": "hyphen",
        "modifiers": { "mandatory": ["command", "shift"], "optional": ["caps_lock"] }
      },
      "to": [
        { "shell_command": "$HOME/.config/cmux/scripts/ghostty-opacity.sh hold - 0.02" }
      ],
      "to_after_key_up": [
        { "shell_command": "$HOME/.config/cmux/scripts/ghostty-opacity.sh release" }
      ],
      "conditions": [
        { "type": "frontmost_application_if", "bundle_identifiers": ["^com\\.cmuxterm\\.app$"] }
      ]
    }
  ]
}
```

ポイント:

- `to` で `hold +` / `hold -` を呼ぶことで「キー押下 → 即時 1 ステップ + 連続変更ループ起動」になります。
- `to_after_key_up` で `release` を呼んでループを停止します。これを忘れると指を離した後もずっと変わり続けます。
- `frontmost_application_if` で cmux アプリ (`com.cmuxterm.app`) が最前面のときだけ発火するように制限しています。他アプリで `⌘⇧+` を奪われたくない場合の制約。
- Karabiner の設定ファイルは保存と同時に自動リロードされます。反映されない場合は Karabiner-Elements を一度終了して立ち上げ直してください。
