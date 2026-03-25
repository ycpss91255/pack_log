#!/bin/bash
# 简体中文消息文件 for pack_log.sh

# --- 帮助文本 ---
# shellcheck disable=SC2034
MSG_HELP_USAGE='用法: %s [选项]'
MSG_HELP_OPTIONS='  选项:'
MSG_HELP_NUMBER='    -n, --number                  主机编号 (1-%d)'
MSG_HELP_USERHOST='    -u, --userhost <user@host>    用户与主机 (例: user@host)'
MSG_HELP_LOCAL='    -l, --local                   使用本机模式'
MSG_HELP_START='    -s, --start <YYYYmmdd-HHMMSS>  起始时间 (例: 20260101-000000)'
MSG_HELP_END='    -e, --end <YYYYmmdd-HHMMSS>    结束时间 (例: 20260101-235959)'
MSG_HELP_OUTPUT='    -o, --output <路径>           输出文件夹路径'
MSG_HELP_LANG='    --lang <代码>                 语言 (en, zh-TW, zh-CN, ja)'
MSG_HELP_VERBOSE='    -v, --verbose                 启用详细输出'
MSG_HELP_VERY_VERBOSE='    -vv, --very-verbose           启用更详细输出 (debug)'
MSG_HELP_EXTRA_VERBOSE='    -vvv, --extra-verbose         启用最详细输出 (set -x)'
MSG_HELP_HELP='    -h, --help                    显示此帮助信息并退出'
MSG_HELP_VERSION='    --version                     显示版本并退出'

# --- 软件包 / sudo ---
MSG_CHECKING_SUDO='正在检查 sudo 权限。'
MSG_PKG_ALREADY_INSTALLED='软件包 %s 已安装。'
MSG_PKG_NOT_FOUND='未找到软件包 %s，正在安装...'
MSG_NO_SUDO_ACCESS='没有 sudo 权限来安装 %s。'
MSG_PKG_INSTALL_FAILED='安装软件包 %s 失败。'

# --- 日期格式 ---
MSG_INVALID_DATE_FORMAT='无效的日期格式: %s'
MSG_DATE_FORMAT_FAILED='日期格式化失败: %s'

# --- 远程值 / token ---
MSG_UNKNOWN_TOKEN_TYPE='未知的类型: %s'
MSG_COMMAND_FAILED='命令执行失败: %s'
MSG_INVALID_SPECIAL_STRING='无效的特殊字符串格式: %s'
MSG_UNKNOWN_SPECIAL_STRING='未知的特殊字符串类型: %s'

# --- 文件夹 ---
MSG_FOLDER_CREATE_FAILED='创建文件夹失败: %s'
MSG_HOSTNAME_DATE_FAILED='无法从 %s 获取主机名/日期'

# --- 主机选择 ---
MSG_HOST_USING_LOCAL='使用本机作为目标主机'
MSG_HOST_PROMPT='输入 local、编号 (1-%d) 或 user@host: '
MSG_INVALID_INPUT='无效的输入: %s'
MSG_HOST_NUMBER_RANGE='编号必须在 1 到 %d 之间'
MSG_INVALID_USERHOST='无效的 user@host 格式: %s'

# --- 时间处理 ---
MSG_TIME_PROMPT='输入 %s (YYYYmmdd-HHMMSS): '
MSG_INVALID_TIME_FORMAT='无效的 %s 格式: %s'
MSG_START_BEFORE_END='起始时间 (%s) 必须早于结束时间 (%s)'

# --- SSH ---
MSG_SSH_ATTEMPT='正在尝试 SSH 连接到 %s (第 %d/%d 次)...'
MSG_SSH_SUCCESS='SSH 连接到 %s 成功'
MSG_SSH_KEY_EXISTS='SSH 密钥 %s 存在'
MSG_SSH_PERMISSION_DENIED='SSH 密钥权限被拒，将尝试复制密钥。'
MSG_SSH_HOST_CHANGED='SSH 主机标识已变更，正在移除旧密钥。'
MSG_SSH_FAILED='SSH 连接失败: %s'
MSG_SSH_KEY_NOT_FOUND='SSH 密钥 %s 不存在'
MSG_SSH_KEY_CREATING='正在创建新的 SSH 密钥'
MSG_SSH_KEY_CREATE_WITH='未找到 SSH 密钥 %s，使用 %s 创建中...'
MSG_SSH_KEY_CREATE_FAILED='创建 SSH 密钥 %s 失败'
MSG_SSH_HOST_KEY_REMOVE='正在移除 %s 的现有主机密钥。'
MSG_SSH_HOST_KEY_ADD='正在将 %s 添加到已知主机。'
MSG_SSH_PRIVATE_NOT_FOUND='未找到私钥: %s'
MSG_SSH_PUBLIC_NOT_FOUND='未找到公钥: %s'
MSG_SSH_KEY_INVALID='无效的私钥: %s'
MSG_SSH_KEY_MISMATCH='公钥与私钥不匹配。'
MSG_SSH_COPY_FAILED='复制 SSH 密钥到 %s 失败。'
MSG_SSH_RETRY_FAILED='SSH 重试 %d/%d 失败: %s'
MSG_SSH_FINAL_FAILURE='SSH 连接在 %d 次重试后失败:'

# --- 工具检查 ---
MSG_RSYNC_NOT_AVAILABLE='远程主机上没有 rsync，尝试下一个工具...'
MSG_NO_TRANSFER_TOOLS='没有可用的文件传输工具 (%s)。'

# --- 文件操作 ---
MSG_NO_FILES_IN_RANGE='在时间范围 %s ~ %s 中未找到文件。'
MSG_FILES_SELECTED='从 %d 个候选文件中选取了 %d 个。'
MSG_USER_INPUTS_SUMMARY='用户输入摘要:'
MSG_NO_SAVE_FOLDER='未定义 SAVE_FOLDER，跳过清理。'
MSG_FOLDER_REMOVE_FAILED='移除远程文件夹失败: %s'
MSG_FOLDER_REMOVED='远程文件夹 %s 已成功移除。'
MSG_NO_FILES_TO_COPY='%s 没有文件可复制'
MSG_COPY_FAILED='复制文件到 %s 失败'
MSG_LOCAL_DESTINATION='本机目标文件夹: %s'
MSG_REMOTE_NOT_FOUND='未找到远程文件夹: %s'
MSG_REMOTE_FOLDER_SIZE='远程文件夹 %s 大小: %s'
MSG_UNSUPPORTED_TOOL='不支持的文件传输工具: %s'
MSG_TRANSFER_RETRY='%s 失败 (第 %d/%d 次)，%d 秒后重试...'
MSG_TRANSFER_FAILED='%s 在 %d 次尝试后失败。'
MSG_REMOTE_PRESERVED='远程文件夹已保留: %s:%s'
MSG_RETRIEVE_MANUALLY='请手动取回文件，完成后请删除远程文件夹。'

# --- get_log ---
MSG_PROCESSING='[%d/%d] 处理中: %s'
MSG_NO_FILES_FOUND='[%d/%d] 未找到文件。'
MSG_FOUND_COPYING='[%d/%d] 找到 %d 个文件，复制中...'

# --- 主要步骤 ---
MSG_STEP1='=== 步骤 1/5: 解析目标主机 ==='
MSG_STEP2='=== 步骤 2/5: 验证时间范围 ==='
MSG_STEP3_SSH='=== 步骤 3/5: 建立 SSH 连接 ==='
MSG_STEP3_LOCAL='=== 步骤 3/5: 本机模式 (跳过 SSH) ==='
MSG_STEP4='=== 步骤 4/5: 收集 log 文件 ==='
MSG_STEP5_TRANSFER='=== 步骤 5/5: 传输文件到本机 (%s) ==='
MSG_STEP5_LOCAL='=== 步骤 5/5: 文件已在本机收集完成 ==='
MSG_SUCCESS='打包 log 完成。'
