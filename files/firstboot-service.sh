[Unit]
Description=Auto-install Debian on first boot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firstboot-install.sh
RemainAfterExit=yes
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1

[Install]
WantedBy=multi-user.target
