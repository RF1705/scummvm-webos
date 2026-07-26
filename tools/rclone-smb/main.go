// rclone-smb is a deliberately small rclone build for LG webOS TVs.
package main

import (
	_ "github.com/rclone/rclone/backend/smb"
	"github.com/rclone/rclone/cmd"
	_ "github.com/rclone/rclone/cmd/lsd"
	_ "github.com/rclone/rclone/cmd/mount"
	_ "github.com/rclone/rclone/cmd/obscure"
	_ "github.com/rclone/rclone/cmd/version"
)

func main() {
	cmd.Main()
}
