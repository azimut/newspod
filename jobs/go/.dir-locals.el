((go-mode . ((dape-configs . ((go-debug-newspod-gofetch
                               modes (go-mode go-ts-mode)
                               command "dlv"
                               command-args ("dap" "--listen" "127.0.0.1:55878")
                               command-cwd default-directory
                               host "127.0.0.1"
                               port 55878
                               :buildFlags "-tags 'sqlite_fts5 sqlite_foreign_keys'"
                               :request "launch"
                               :mode "debug"
                               :type "go"
                               :showLog "true"
                               :cwd "/home/sendai/projects/go/newspod/jobs/go/"
                               :program "./..."))))))
