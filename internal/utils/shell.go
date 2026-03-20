package utils

import (
	"strings"
)

// ShellEscape safely escapes shell arguments to prevent command injection
// 该函数将参数安全地包裹在单引号中，并转义内部的单引号
func ShellEscape(arg string) string {
	// 如果参数为空，返回空字符串
	if arg == "" {
		return "''"
	}

	// 检查是否包含需要特殊处理的字符
	needsQuoting := false
	for _, r := range arg {
		if r == ' ' || r == '\t' || r == '\n' ||
			r == '\'' || r == '"' || r == '\\' ||
			r == '$' || r == '`' || r == '|' ||
			r == '&' || r == ';' || r == '<' ||
			r == '>' || r == '(' || r == ')' ||
			r == '{' || r == '}' || r == '[' ||
			r == ']' || r == '*' || r == '?' ||
			r == '#' || r == '~' || r == '=' ||
			r == '!' {
			needsQuoting = true
			break
		}
	}

	if !needsQuoting {
		return arg
	}

	// 使用单引号包裹，并转义内部的单引号
	// ' 变成 '\''
	escaped := strings.ReplaceAll(arg, "'", "'\\''")
	return "'" + escaped + "'"
}

// ShellEscapeSlice escapes multiple shell arguments
func ShellEscapeSlice(args []string) []string {
	escaped := make([]string, len(args))
	for i, arg := range args {
		escaped[i] = ShellEscape(arg)
	}
	return escaped
}

// ValidateShellCommand checks if a command contains potentially dangerous patterns
// 返回 true 表示检测到可疑模式
func ValidateShellCommand(cmd string) bool {
	dangerousPatterns := []string{
		";", "|", "&", "$", "`", "(", ")", "{", "}",
		"<", ">", "\\", "!", "~", "*", "?", "[", "]",
	}

	for _, pattern := range dangerousPatterns {
		if strings.Contains(cmd, pattern) {
			return true
		}
	}

	return false
}
