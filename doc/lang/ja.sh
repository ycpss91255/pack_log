#!/bin/bash
# 日本語メッセージファイル for pack_log.sh

# --- ヘルプテキスト ---
# shellcheck disable=SC2034
MSG_HELP_USAGE='使用法: %s [オプション]'
MSG_HELP_OPTIONS='  オプション:'
MSG_HELP_NUMBER='    -n, --number                  ホスト番号 (1-%d)'
MSG_HELP_USERHOST='    -u, --userhost <user@host>    ユーザーとホスト (例: user@host)'
MSG_HELP_LOCAL='    -l, --local                   ローカルモードを使用'
MSG_HELP_START='    -s, --start <YYmmdd-HHMM>  開始時刻 (例: 260101-0000)'
MSG_HELP_END='    -e, --end <YYmmdd-HHMM>    終了時刻 (例: 260101-2359)'
MSG_HELP_OUTPUT='    -o, --output <パス>           出力フォルダパス（<num>, <name>, <date:fmt> 対応）'
MSG_HELP_LANG='    --lang <コード>               言語 (en, zh-TW, zh-CN, ja)'
MSG_HELP_VERBOSE='    -v, --verbose                 詳細出力を有効化'
MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           より詳細な出力を有効化 (debug)'
MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         最も詳細な出力を有効化 (set -x)'
MSG_HELP_DRY_RUN='    --dry-run                     シミュレーション実行（ファイルのコピー・転送なし）'
MSG_HELP_HELP='    -h, --help                    このヘルプメッセージを表示して終了'
MSG_HELP_VERSION='    --version                     バージョンを表示して終了'

# --- パッケージ / sudo ---
MSG_CHECKING_SUDO='sudo アクセスを確認中。'
MSG_PKG_ALREADY_INSTALLED='パッケージ %s はインストール済みです。'
MSG_PKG_NOT_FOUND='パッケージ %s が見つかりません。インストール中...'
MSG_NO_SUDO_ACCESS='%s をインストールする sudo 権限がありません。'
MSG_PKG_INSTALL_FAILED='パッケージ %s のインストールに失敗しました。'

# --- 日付フォーマット ---
MSG_INVALID_DATE_FORMAT='無効な日付形式: %s'
MSG_DATE_FORMAT_FAILED='日付のフォーマットに失敗: %s'

# --- リモート値 / トークン ---
MSG_UNKNOWN_TOKEN_TYPE='不明なタイプ: %s'
MSG_COMMAND_FAILED='コマンド実行失敗: %s'
MSG_INVALID_SPECIAL_STRING='無効な特殊文字列形式: %s'
MSG_UNKNOWN_SPECIAL_STRING='不明な特殊文字列タイプ: %s'
MSG_TOKEN_NUM_NO_HOST='トークン %s には -n（ホスト番号）が必要です。-u または -l 使用時は無視されます'

# --- フォルダ ---
MSG_FOLDER_CREATE_FAILED='フォルダの作成に失敗: %s'
MSG_HOSTNAME_DATE_FAILED='%s からホスト名/日付を取得できません'

# --- ホスト選択 ---
MSG_HOST_USING_LOCAL='ローカルマシンをホストとして使用'
MSG_HOST_PROMPT='local、番号 (1-%d)、または user@host を入力: '
MSG_INVALID_INPUT='無効な入力: %s'
MSG_HOST_NUMBER_RANGE='番号は 1 から %d の間で指定してください'
MSG_INVALID_USERHOST='無効な user@host 形式: %s'

# --- 時刻処理 ---
MSG_TIME_PROMPT='%s を入力 (YYmmdd-HHMM): '
MSG_INVALID_TIME_FORMAT='無効な %s 形式: %s'
MSG_START_BEFORE_END='開始時刻 (%s) は終了時刻 (%s) より前でなければなりません'

# --- SSH ---
MSG_SSH_ATTEMPT='%s への SSH 接続を試行中 (第 %d/%d 回)...'
MSG_SSH_SUCCESS='%s への SSH 接続成功'
MSG_SSH_KEY_EXISTS='SSH キー %s が存在します'
MSG_SSH_PERMISSION_DENIED='SSH キーの権限が拒否されました。キーのコピーを試みます。'
MSG_SSH_HOST_CHANGED='SSH ホスト識別が変更されました。古いキーを削除中。'
MSG_SSH_FAILED='SSH 接続失敗: %s'
MSG_SSH_KEY_NOT_FOUND='SSH キー %s が存在しません'
MSG_SSH_KEY_CREATING='新しい SSH キーを作成中'
MSG_SSH_KEY_CREATE_WITH='SSH キー %s が見つかりません。%s で作成中...'
MSG_SSH_KEY_CREATE_FAILED='SSH キー %s の作成に失敗'
MSG_SSH_HOST_KEY_REMOVE='%s の既存ホストキーを削除中。'
MSG_SSH_HOST_KEY_ADD='%s を既知のホストに追加中。'
MSG_SSH_PRIVATE_NOT_FOUND='秘密鍵が見つかりません: %s'
MSG_SSH_PUBLIC_NOT_FOUND='公開鍵が見つかりません: %s'
MSG_SSH_KEY_INVALID='無効な秘密鍵: %s'
MSG_SSH_KEY_MISMATCH='公開鍵と秘密鍵が一致しません。'
MSG_SSH_COPY_FAILED='SSH キーの %s へのコピーに失敗。'
MSG_SSH_RETRY_FAILED='SSH リトライ %d/%d 失敗: %s'
MSG_SSH_FINAL_FAILURE='%d 回のリトライ後 SSH 接続に失敗:'

# --- ツールチェック ---
MSG_RSYNC_NOT_AVAILABLE='リモートホストに rsync がありません。次のツールを試行中...'
MSG_NO_TRANSFER_TOOLS='利用可能なファイル転送ツール (%s) がありません。'

# --- ファイル操作 ---
MSG_NO_FILES_IN_RANGE='時間範囲 %s ~ %s に該当するファイルが見つかりません。'
MSG_FILES_SELECTED='%d 個の候補から %d 個のファイルを選択しました。'
MSG_USER_INPUTS_SUMMARY='ユーザー入力サマリー:'
MSG_NO_SAVE_FOLDER='SAVE_FOLDER が未定義です。クリーンアップをスキップします。'
MSG_FOLDER_REMOVE_FAILED='リモートフォルダの削除に失敗: %s'
MSG_FOLDER_REMOVED='リモートフォルダ %s を正常に削除しました。'
MSG_NO_FILES_TO_COPY='%s にコピーするファイルがありません'
MSG_COPY_FAILED='%s へのファイルコピーに失敗'
MSG_LOCAL_DESTINATION='ローカル保存先フォルダ: %s'
MSG_REMOTE_NOT_FOUND='リモートフォルダが見つかりません: %s'
MSG_REMOTE_FOLDER_SIZE='リモートフォルダ %s のサイズ: %s'
MSG_UNSUPPORTED_TOOL='サポートされていないファイル転送ツール: %s'
MSG_TRANSFER_RETRY='%s 失敗 (第 %d/%d 回)、%d 秒後にリトライ...'
MSG_TRANSFER_FAILED='%s は %d 回の試行後に失敗しました。'
MSG_REMOTE_PRESERVED='リモートフォルダを保持: %s:%s'
MSG_RETRIEVE_MANUALLY='手動で取得し、完了後にリモートフォルダを削除してください。'

# --- get_log ---
MSG_EMPTY_PATH='[%d/%d] 解決済みパスが空です。スキップします。'
MSG_PROCESSING='[%d/%d] 処理中: %s'
MSG_NO_FILES_FOUND='[%d/%d] ファイルが見つかりません。'
MSG_FOUND_COPYING='[%d/%d] %d 個のファイルが見つかりました。コピー中...'

# --- メインステップ ---
MSG_STEP1='=== ステップ 1/5: ターゲットホストの解決 ==='
MSG_STEP2='=== ステップ 2/5: 時間範囲の検証 ==='
MSG_STEP3_SSH='=== ステップ 3/5: SSH 接続の確立 ==='
MSG_STEP3_LOCAL='=== ステップ 3/5: ローカルモード (SSH スキップ) ==='
MSG_STEP4='=== ステップ 4/5: ログファイルの収集 ==='
MSG_STEP5_TRANSFER='=== ステップ 5/5: ローカルへファイル転送中 (%s) ==='
MSG_STEP5_LOCAL='=== ステップ 5/5: ローカルでファイル収集完了 ==='
MSG_SUCCESS='ログのパッケージングが正常に完了しました。'

# --- ドライラン ---
MSG_DRY_RUN_BANNER='*** ドライランモード — ファイルのコピー・転送は行いません ***'
MSG_DRY_RUN_RESOLVED='[ドライラン] 解決済みパス：%s'
MSG_DRY_RUN_PATTERN='[ドライラン] ファイルパターン：%s'
MSG_DRY_RUN_DIR_NOT_FOUND='[ドライラン] ディレクトリが見つかりません：%s'
MSG_DRY_RUN_WOULD_COPY='[ドライラン] %d 個のファイルをコピー予定：'
MSG_DRY_RUN_TOTAL='[ドライラン] 収集予定の合計ファイル数：%d'
MSG_DRY_RUN_COMPLETE='*** ドライラン完了 — 変更は行われていません ***'
