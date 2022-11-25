(module telescope-ctags)

(local finders (require :telescope.finders))
(local conf (. (require :telescope.config) :values))
(local pickers (require :telescope.pickers))
(local entry_display (require :telescope.pickers.entry_display))
(local strings (require :plenary.strings))
(local sorters (require :telescope.sorters))

(defn- create-cmd [name func]
       (let [defParams {:nargs "*" :range true :complete :file}]
         (vim.api.nvim_create_user_command name func defParams)))

(var defaultSettings {:path (vim.fn.expand "%:p")
                      :exclude []
                      :debug false
                      :root :.git
                      :type ""
                      :prompt_title :ctags
                      :show_file false
                      :show_line true
                      :show_scope false
                      :cmd [:ctags
                            :--recurse
                            :--fields=+n
                            :--quiet=yes
                            :--guess-language-eagerly
                            :-f-
                            :--output-format=json]})

(var settings {})
(defn- debug [v] (when settings.debug
                   (print (vim.inspect v))))

(defn- build-shell-cmd [opts] (let [cmd (vim.deepcopy opts.cmd)]
                                (each [key value (pairs opts.exclude)]
                                  (table.insert cmd (.. :--exclude= value)))
                                (when (not= opts.type "")
                                  (when (not= opts.filetype nil)
                                    (table.insert cmd
                                                  (.. "--" opts.filetype
                                                      :-kinds= opts.type))))
                                (when (not= opts.filetype nil)
                                  (table.insert cmd
                                                (.. :--languages "="
                                                    opts.filetype)))
                                (table.insert cmd opts.path)
                                (debug (vim.fn.join cmd " "))
                                cmd))

(defn- run-shell-cmd [cmd] (vim.fn.systemlist cmd))

(defn- common-part [str1 str2] (var i 1)
       (when (not= str1 nil)
         (each [c (str1:gmatch ".")]
           (when (= (string.sub str2 i i) c)
             (set i (+ i 1))))
         (string.sub str1 1 (- i 1))))

(fn build-make-display [confOpts]
  (local opts confOpts)
  (lambda [entry]
    (local display-items [{:remaining true} {:remaining true}])
    (let [items [[(.. entry.value.type " ") :TelescopeResultsVariable]]]
      (when (. opts :show_scope)
        (let [scope (vim.trim entry.value.scope)]
          (when (not= scope "")
            (table.insert display-items {:remaining true})
            (table.insert items
                          [(.. entry.value.scope " ") :TelescopeResultsStruct]))))
      (table.insert items [(.. entry.value.name " ") :TelescopeResultsFunction])
      (when (. opts :show_file)
        (let [estimatedLen (- (string.len entry.filename)
                              (string.len opts.path))]
          (let [filename (strings.truncate entry.filename estimatedLen "" -1)]
            (table.insert display-items {:remaining true})
            (table.insert items [filename :TelescopeResultsComment]))))
      (when (. opts :show_line)
        (table.insert display-items {:remaining true})
        (table.insert items
                      [(.. ":" entry.value.line) :TelescopeResultsComment]))
      ((entry_display.create {:separator "" :items display-items}) items))))

(defn- prepare-entry-to-telescope-display [opts entry]
       (when (string.match entry "{")
         (match (pcall vim.json.decode
                       (.. "{" (string.gsub (string.gsub entry "}" "") "{" "")
                           "}"))
           (true decoded) (let [value {:type (. decoded :kind)
                                       :line (tonumber decoded.line)
                                       :name (. decoded :name)
                                       :pattern (. decoded :pattern)
                                       :filename decoded.path}]
                            (when (vim.F.if_nil (. opts :show_scope) false)
                              (tset value :scope
                                    (vim.F.if_nil (. decoded :scope) "")))
                            {:filename (. value :filename)
                             :lnum (tonumber (. value :line))
                             : value
                             :display (build-make-display opts)
                             :ordinal (.. (. value :line) (. value :type)
                                          (. value :name) (. value :filename))})
           (false errMsg) (error (string.format "error %s on parse ctag results %s"
                                                errMsg entry)))))

(defn- filter-empty [items] (let [result {}]
                              (each [key value (pairs items)]
                                (when (not= value "")
                                  (table.insert result value)))
                              result))

(defn- items-common-part [items] (when (> (table.getn items) 0)
                                   (var commonPart
                                        (. (. (. items 1) :value) :scope))
                                   (each [key value (pairs items)]
                                     (when (not= key (table.getn items))
                                       (let [nextValue (. items (+ key 1))]
                                         (set commonPart
                                              (common-part commonPart
                                                           nextValue.value.scope)))))
                                   commonPart))

(defn- trim [s sym] (let [res (string.gsub (string.gsub s (.. "^" sym) "")
                                           (.. sym "$") "")]
                      res))

(defn- remove-items-common-part [items common-part]
       (when (not= common-part nil)
         (let [res (vim.tbl_map (lambda [entry]
                                  (tset entry.value :scope
                                        (trim (string.gsub entry.value.scope
                                                           common-part "" 1)
                                              "%."))
                                  entry) items)]
           res)) (when (= common-part nil)
                         items))

(defn RunCtags [initOpts] (let [opts (vim.tbl_deep_extend :force settings
                                                          (vim.F.if_nil initOpts
                                                                        {}))]
                            (let [items (filter-empty (run-shell-cmd (build-shell-cmd opts)))]
                              (var finalItems {})
                              (each [key value (pairs items)]
                                (table.insert finalItems
                                              (prepare-entry-to-telescope-display opts
                                                                                  value)))
                              (remove-items-common-part finalItems
                                                        (items-common-part finalItems))
                              (when (and (. opts :show_scope)
                                         (. opts :scope_filter))
                                (set finalItems
                                     (vim.tbl_filter (lambda [e]
                                                       (opts.scope_filter e.value.scope))
                                                     finalItems)))
                              (let [picker (pickers.new opts
                                                        {:prompt_title opts.prompt_title
                                                         :finder (finders.new_table {:results finalItems
                                                                                     :entry_maker (lambda [entry]
                                                                                                    entry)})
                                                         :sorter (sorters.get_generic_fuzzy_sorter)})]
                                (picker:find)))))

(defn RunCtagsFuncFile [initOpts]
      (let [defaults {:path (vim.fn.expand "%:p") :type :f :show_scope true}]
        (let [opts (vim.tbl_deep_extend :force defaults
                                        (vim.F.if_nil initOpts {}))]
          (RunCtags opts))))

(defn RunCtagsAllFile [initOpts]
      (let [defaults {:path (vim.fn.expand "%:p") :show_scope true}]
        (let [opts (vim.tbl_deep_extend :force defaults
                                        (vim.F.if_nil initOpts {}))]
          (RunCtags opts))))

(defn RunCtagsFuncPackage [initOpts]
      (let [defaults {:path (vim.fn.expand "%:p:h")
                      :type :f
                      :show_scope true
                      :show_file true}]
        (let [opts (vim.tbl_deep_extend :force defaults
                                        (vim.F.if_nil initOpts {}))]
          (RunCtags opts))))

(defn RunCtagsAllPackage [initOpts]
      (let [defaults {:path (vim.fn.expand "%:p:h")
                      :show_scope true
                      :show_file true}]
        (let [opts (vim.tbl_deep_extend :force defaults
                                        (vim.F.if_nil initOpts {}))]
          (RunCtags opts))))

(defn RunCtagsRoot [initOpts]
      (let [defaults {:path (vim.fn.finddir (.. settings.root "/..")
                                            (.. (vim.fn.expand "%:p:h") ";"))
                      :type :f
                      :show_scope true
                      :show_file true}]
        (let [opts (vim.tbl_deep_extend :force defaults
                                        (vim.F.if_nil initOpts {}))]
          (RunCtags opts))))

(defn RunCtagsPackageCurWorldScope [initOpts]
      (let [defaults {:scope_filter (lambda [v]
                                      (string.match v
                                                    (vim.call :expand :<cword>)))}]
        (let [opts (vim.tbl_deep_extend :force defaults
                                        (vim.F.if_nil initOpts {}))]
          (RunCtagsFuncPackage opts))))

(defn init [] (set settings defaultSettings)
      (create-cmd :CtagsRoot RunCtagsRoot)
      (create-cmd :CtagsPackageCurWorldScope RunCtagsPackageCurWorldScope)
      (create-cmd :CtagsFuncPackage RunCtagsFuncPackage)
      (create-cmd :CtagsAllPackage RunCtagsAllPackage)
      (create-cmd :CtagsFuncFile RunCtagsFuncFile)
      (create-cmd :CtagsAllFile RunCtagsAllFile)
      (create-cmd :CtagsCore RunCtags) nil)

(defn setup [opts]
      (set settings
           (vim.tbl_deep_extend :force settings (vim.F.if_nil opts {}))))
