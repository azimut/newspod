((go-mode . ((dape-configs . ((go-debug-newspod-gofetch
                               modes (go-mode go-ts-mode)
                               command "dlv"
                               command-args ("dap" "--listen" "127.0.0.1::autoport")
                               command-cwd default-directory
                               host "127.0.0.1"
                               port :autoport
                               :buildFlags "-tags 'sqlite_fts5 sqlite_foreign_keys'"
                               :request "launch"
                               :mode "debug"
                               :type "go"
                               :showLog "true"
                               :cwd (concat default-directory "/..") ; "/src/.."
                               :program "./..."))))))
