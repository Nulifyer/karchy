//go:build !windows

package webapp

import (
	"bufio"
	"os"
	"strings"
)

// readLine reads a line of input from stdin.
func readLine() string {
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	return strings.TrimSpace(line)
}
