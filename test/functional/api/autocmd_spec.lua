local helpers = require('test.functional.helpers')(after_each)

local clear = helpers.clear
local command = helpers.command
local eq = helpers.eq
local neq = helpers.neq
local exec_lua = helpers.exec_lua
local matches = helpers.matches
local meths = helpers.meths
local source = helpers.source
local pcall_err = helpers.pcall_err

before_each(clear)

describe('autocmd api', function()
  describe('nvim_create_autocmd', function()
    it('does not allow "command" and "callback" in the same autocmd', function()
      local ok, _ = pcall(meths.create_autocmd, "BufReadPost", {
        pattern = "*.py,*.pyi",
        command = "echo 'Should Have Errored",
        callback = "not allowed",
      })

      eq(false, ok)
    end)

    it('doesnt leak when you use ++once', function()
      eq(1, exec_lua([[
        local count = 0

        vim.api.nvim_create_autocmd("FileType", {
          pattern = "*",
          callback = function() count = count + 1 end,
          once = true
        })

        vim.cmd "set filetype=txt"
        vim.cmd "set filetype=python"

        return count
      ]], {}))
    end)

    it('allows passing buffer by key', function()
      meths.set_var('called', 0)

      meths.create_autocmd("FileType", {
        command = "let g:called = g:called + 1",
        buffer = 0,
      })

      meths.command "set filetype=txt"
      eq(1, meths.get_var('called'))

      -- switch to a new buffer
      meths.command "new"
      meths.command "set filetype=python"

      eq(1, meths.get_var('called'))
    end)

    it('does not allow passing buffer and patterns', function()
      local ok = pcall(meths.create_autocmd, "Filetype", {
        command = "let g:called = g:called + 1",
        buffer = 0,
        pattern = "*.py",
      })

      eq(false, ok)
    end)

    it('does not allow passing invalid buffers', function()
      local ok, msg = pcall(meths.create_autocmd, "Filetype", {
        command = "let g:called = g:called + 1",
        buffer = -1,
      })

      eq(false, ok)
      matches('Invalid buffer id', msg)
    end)

    it('errors on non-functions for cb', function()
      eq(false, pcall(exec_lua, [[
        vim.api.nvim_create_autocmd("BufReadPost", {
          pattern = "*.py,*.pyi",
          callback = 5,
        })
      ]]))
    end)

    it('allow passing pattern and <buffer> in same pattern', function()
      local ok = pcall(meths.create_autocmd, "BufReadPost", {
        pattern = "*.py,<buffer>",
        command = "echo 'Should Not Error'"
      })

      eq(true, ok)
    end)

    it('should handle multiple values as comma separated list', function()
      meths.create_autocmd("BufReadPost", {
        pattern = "*.py,*.pyi",
        command = "echo 'Should Not Have Errored'"
      })

      -- We should have one autocmd for *.py and one for *.pyi
      eq(2, #meths.get_autocmds { event = "BufReadPost" })
    end)

    it('should handle multiple values as array', function()
      meths.create_autocmd("BufReadPost", {
        pattern = { "*.py", "*.pyi", },
        command = "echo 'Should Not Have Errored'"
      })

      -- We should have one autocmd for *.py and one for *.pyi
      eq(2, #meths.get_autocmds { event = "BufReadPost" })
    end)

    describe('desc', function()
      it('can add description to one autocmd', function()
        meths.create_autocmd("BufReadPost", {
          pattern = "*.py",
          command = "echo 'Should Not Have Errored'",
          desc = "Can show description",
        })

        eq("Can show description", meths.get_autocmds { event = "BufReadPost" }[1].desc)
      end)

      it('can add description to multiple autocmd', function()
        meths.create_autocmd("BufReadPost", {
          pattern = {"*.py", "*.pyi"},
          command = "echo 'Should Not Have Errored'",
          desc = "Can show description",
        })

        local aus = meths.get_autocmds { event = "BufReadPost" }
        eq(2, #aus)
        eq("Can show description", aus[1].desc)
        eq("Can show description", aus[2].desc)
      end)
    end)

    pending('script and verbose settings', function()
      it('marks API client', function()
        meths.create_autocmd("BufReadPost", {
          pattern = "*.py",
          command = "echo 'Should Not Have Errored'",
          desc = "Can show description",
        })

        local aus = meths.get_autocmds { event = "BufReadPost" }
        eq(1, #aus, aus)
      end)
    end)
  end)

  describe('nvim_get_autocmds', function()
    describe('events', function()
      it('should return one autocmd when there is only one for an event', function()
        command [[au! InsertEnter]]
        command [[au InsertEnter * :echo "1"]]

        local aus = meths.get_autocmds { event = "InsertEnter" }
        eq(1, #aus)
      end)

      it('should return two autocmds when there are two for an event', function()
        command [[au! InsertEnter]]
        command [[au InsertEnter * :echo "1"]]
        command [[au InsertEnter * :echo "2"]]

        local aus = meths.get_autocmds { event = "InsertEnter" }
        eq(2, #aus)
      end)

      it('should return the same thing if you use string or list', function()
        command [[au! InsertEnter]]
        command [[au InsertEnter * :echo "1"]]
        command [[au InsertEnter * :echo "2"]]

        local string_aus = meths.get_autocmds { event = "InsertEnter" }
        local array_aus = meths.get_autocmds { event = { "InsertEnter" } }
        eq(string_aus, array_aus)
      end)

      it('should return two autocmds when there are two for an event', function()
        command [[au! InsertEnter]]
        command [[au! InsertLeave]]
        command [[au InsertEnter * :echo "1"]]
        command [[au InsertEnter * :echo "2"]]

        local aus = meths.get_autocmds { event = { "InsertEnter", "InsertLeave" } }
        eq(2, #aus)
      end)

      it('should return different IDs for different autocmds', function()
        command [[au! InsertEnter]]
        command [[au! InsertLeave]]
        command [[au InsertEnter * :echo "1"]]
        source [[
          call nvim_create_autocmd("InsertLeave", #{
            \ command: ":echo 2",
            \ })
        ]]

        local aus = meths.get_autocmds { event = { "InsertEnter", "InsertLeave" } }
        local first = aus[1]
        eq(first.id, nil)

        -- TODO: Maybe don't have this number, just assert it's not nil
        local second = aus[2]
        neq(second.id, nil)

        meths.del_autocmd(second.id)
        local new_aus = meths.get_autocmds { event = { "InsertEnter", "InsertLeave" } }
        eq(1, #new_aus)
        eq(first, new_aus[1])
      end)

      it('should return event name', function()
        command [[au! InsertEnter]]
        command [[au InsertEnter * :echo "1"]]

        local aus = meths.get_autocmds { event = "InsertEnter" }
        eq({ { buflocal = false, command = ':echo "1"', event = "InsertEnter", once = false, pattern = "*" } }, aus)
      end)

      it('should work with buffer numbers', function()
        command [[new]]
        command [[au! InsertEnter]]
        command [[au InsertEnter <buffer=1> :echo "1"]]
        command [[au InsertEnter <buffer=2> :echo "2"]]

        local aus = meths.get_autocmds { event = "InsertEnter", buffer = 0 }
        eq({{
          buffer = 2,
          buflocal = true,
          command = ':echo "2"',
          event = 'InsertEnter',
          once = false,
          pattern = '<buffer=2>',
        }}, aus)

        aus = meths.get_autocmds { event = "InsertEnter", buffer = 1 }
        eq({{
          buffer = 1,
          buflocal = true,
          command = ':echo "1"',
          event = "InsertEnter",
          once = false,
          pattern = "<buffer=1>",
        }}, aus)

        aus = meths.get_autocmds { event = "InsertEnter", buffer = { 1, 2 } }
        eq({{
          buffer = 1,
          buflocal = true,
          command = ':echo "1"',
          event = "InsertEnter",
          once = false,
          pattern = "<buffer=1>",
        }, {
          buffer = 2,
          buflocal = true,
          command = ':echo "2"',
          event = "InsertEnter",
          once = false,
          pattern = "<buffer=2>",
        }}, aus)

        eq("Invalid value for 'buffer': must be an integer or array of integers", pcall_err(meths.get_autocmds, { event = "InsertEnter", buffer = "foo" }))
        eq("Invalid value for 'buffer': must be an integer", pcall_err(meths.get_autocmds, { event = "InsertEnter", buffer = { "foo", 42 } }))
        eq("Invalid buffer id: 42", pcall_err(meths.get_autocmds, { event = "InsertEnter", buffer = { 42 } }))

        local bufs = {}
        for _ = 1, 257 do
          table.insert(bufs, meths.create_buf(true, false))
        end

        eq("Too many buffers. Please limit yourself to 256 or fewer", pcall_err(meths.get_autocmds, { event = "InsertEnter", buffer = bufs }))
      end)
    end)

    describe('groups', function()
      before_each(function()
        command [[au! InsertEnter]]

        command [[au InsertEnter * :echo "No Group"]]

        command [[augroup GroupOne]]
        command [[  au InsertEnter * :echo "GroupOne:1"]]
        command [[augroup END]]

        command [[augroup GroupTwo]]
        command [[  au InsertEnter * :echo "GroupTwo:2"]]
        command [[  au InsertEnter * :echo "GroupTwo:3"]]
        command [[augroup END]]
      end)

      it('should return all groups if no group is specified', function()
        local aus = meths.get_autocmds { event = "InsertEnter" }
        if #aus ~= 4 then
          eq({}, aus)
        end

        eq(4, #aus)
      end)

      it('should return only the group specified', function()
        local aus = meths.get_autocmds {
          event = "InsertEnter",
          group = "GroupOne",
        }

        eq(1, #aus)
        eq([[:echo "GroupOne:1"]], aus[1].command)
      end)

      it('should return only the group specified, multiple values', function()
        local aus = meths.get_autocmds {
          event = "InsertEnter",
          group = "GroupTwo",
        }

        eq(2, #aus)
        eq([[:echo "GroupTwo:2"]], aus[1].command)
        eq([[:echo "GroupTwo:3"]], aus[2].command)
      end)
    end)

    describe('groups: 2', function()
      it('raises error for undefined augroup', function()
        local success, code = unpack(meths.exec_lua([[
          return {pcall(function()
            vim.api.nvim_create_autocmd("FileType", {
              pattern = "*",
              group = "NotDefined",
              command = "echo 'hello'",
            })
          end)}
        ]], {}))

        eq(false, success)
        matches('invalid augroup: NotDefined', code)
      end)
    end)

    describe('patterns', function()
      before_each(function()
        command [[au! InsertEnter]]

        command [[au InsertEnter *        :echo "No Group"]]
        command [[au InsertEnter *.one    :echo "GroupOne:1"]]
        command [[au InsertEnter *.two    :echo "GroupTwo:2"]]
        command [[au InsertEnter *.two    :echo "GroupTwo:3"]]
        command [[au InsertEnter <buffer> :echo "Buffer"]]
      end)

      it('should should return for literal match', function()
        local aus = meths.get_autocmds {
          event = "InsertEnter",
          pattern = "*"
        }

        eq(1, #aus)
        eq([[:echo "No Group"]], aus[1].command)
      end)

      it('should return for multiple matches', function()
        -- vim.api.nvim_get_autocmds
        local aus = meths.get_autocmds {
          event = "InsertEnter",
          pattern = { "*.one", "*.two" },
        }

        eq(3, #aus)
        eq([[:echo "GroupOne:1"]], aus[1].command)
        eq([[:echo "GroupTwo:2"]], aus[2].command)
        eq([[:echo "GroupTwo:3"]], aus[3].command)
      end)

      it('should work for buffer autocmds', function()
        local normalized_aus = meths.get_autocmds {
          event = "InsertEnter",
          pattern = "<buffer=1>",
        }

        local raw_aus = meths.get_autocmds {
          event = "InsertEnter",
          pattern = "<buffer>",
        }

        local zero_aus = meths.get_autocmds {
          event = "InsertEnter",
          pattern = "<buffer=0>",
        }

        eq(normalized_aus, raw_aus)
        eq(normalized_aus, zero_aus)
        eq([[:echo "Buffer"]], normalized_aus[1].command)
      end)
    end)
  end)

  describe('nvim_do_autocmd', function()
    it("can trigger builtin autocmds", function()
      meths.set_var("autocmd_executed", false)

      meths.create_autocmd("BufReadPost", {
        pattern = "*",
        command = "let g:autocmd_executed = v:true",
      })

      eq(false, meths.get_var("autocmd_executed"))
      meths.do_autocmd("BufReadPost", {})
      eq(true, meths.get_var("autocmd_executed"))
    end)

    it("can pass the buffer", function()
      meths.set_var("buffer_executed", -1)
      eq(-1, meths.get_var("buffer_executed"))

      meths.create_autocmd("BufLeave", {
        pattern = "*",
        command = 'let g:buffer_executed = +expand("<abuf>")',
      })

      -- Doesn't execute for other non-matching events
      meths.do_autocmd("CursorHold", { buffer = 1 })
      eq(-1, meths.get_var("buffer_executed"))

      meths.do_autocmd("BufLeave", { buffer = 1 })
      eq(1, meths.get_var("buffer_executed"))
    end)

    it("can pass the filename, pattern match", function()
      meths.set_var("filename_executed", 'none')
      eq('none', meths.get_var("filename_executed"))

      meths.create_autocmd("BufEnter", {
        pattern = "*.py",
        command = 'let g:filename_executed = expand("<afile>")',
      })

      -- Doesn't execute for other non-matching events
      meths.do_autocmd("CursorHold", { buffer = 1 })
      eq('none', meths.get_var("filename_executed"))

      meths.command('edit __init__.py')
      eq('__init__.py', meths.get_var("filename_executed"))
    end)

    it('cannot pass buf and fname', function()
      local ok = pcall(meths.do_autocmd, "BufReadPre", { pattern = "literally_cannot_error.rs", buffer = 1 })
      eq(false, ok)
    end)

    it("can pass the filename, exact match", function()
      meths.set_var("filename_executed", 'none')
      eq('none', meths.get_var("filename_executed"))

      meths.command('edit other_file.txt')
      meths.command('edit __init__.py')
      eq('none', meths.get_var("filename_executed"))

      meths.create_autocmd("CursorHoldI", {
        pattern = "__init__.py",
        command = 'let g:filename_executed = expand("<afile>")',
      })

      -- Doesn't execute for other non-matching events
      meths.do_autocmd("CursorHoldI", { buffer = 1 })
      eq('none', meths.get_var("filename_executed"))

      meths.do_autocmd("CursorHoldI", { buffer = tonumber(meths.get_current_buf()) })
      eq('__init__.py', meths.get_var("filename_executed"))

      -- Reset filename
      meths.set_var("filename_executed", 'none')

      meths.do_autocmd("CursorHoldI", { pattern = '__init__.py' })
      eq('__init__.py', meths.get_var("filename_executed"))
    end)

    it("works with user autocmds", function()
      meths.set_var("matched", 'none')

      meths.create_autocmd("User", {
        pattern = "TestCommand",
        command = 'let g:matched = "matched"'
      })

      meths.do_autocmd("User", { pattern = "OtherCommand" })
      eq('none', meths.get_var('matched'))
      meths.do_autocmd("User", { pattern = "TestCommand" })
      eq('matched', meths.get_var('matched'))
    end)
  end)

  describe('nvim_create_augroup', function()
    before_each(function()
      clear()

      meths.set_var('executed', 0)
    end)

    local make_counting_autocmd = function(opts)
      opts = opts or {}

      local resulting = {
        pattern = "*",
        command = "let g:executed = g:executed + 1",
      }

      resulting.group = opts.group
      resulting.once = opts.once

      meths.create_autocmd("FileType", resulting)
    end

    local set_ft = function(ft)
      ft = ft or "txt"
      source(string.format("set filetype=%s", ft))
    end

    local get_executed_count = function()
      return meths.get_var('executed')
    end

    it('can be added in a group', function()
      local augroup = "TestGroup"
      meths.create_augroup(augroup, { clear = true })
      make_counting_autocmd { group = augroup }

      set_ft("txt")
      set_ft("python")

      eq(get_executed_count(), 2)
    end)

    it('works getting called multiple times', function()
      make_counting_autocmd()
      set_ft()
      set_ft()
      set_ft()

      eq(get_executed_count(), 3)
    end)

    it('handles ++once', function()
      make_counting_autocmd {once = true}
      set_ft('txt')
      set_ft('help')
      set_ft('txt')
      set_ft('help')

      eq(get_executed_count(), 1)
    end)

    it('errors on unexpected keys', function()
      local success, code = pcall(meths.create_autocmd, "FileType", {
        pattern = "*",
        not_a_valid_key = "NotDefined",
      })

      eq(false, success)
      matches('not_a_valid_key', code)
    end)

    it('can execute simple callback', function()
      exec_lua([[
        vim.g.executed = false

        vim.api.nvim_create_autocmd("FileType", {
          pattern = "*",
          callback = function() vim.g.executed = true end,
        })
      ]], {})


      eq(true, exec_lua([[
        vim.cmd "set filetype=txt"
        return vim.g.executed
      ]], {}))
    end)

    it('calls multiple lua callbacks for the same autocmd execution', function()
      eq(4, exec_lua([[
        local count = 0
        local counter = function()
          count = count + 1
        end

        vim.api.nvim_create_autocmd("FileType", {
          pattern = "*",
          callback = counter,
        })

        vim.api.nvim_create_autocmd("FileType", {
          pattern = "*",
          callback = counter,
        })

        vim.cmd "set filetype=txt"
        vim.cmd "set filetype=txt"

        return count
      ]], {}))
    end)

    it('properly releases functions with ++once', function()
      exec_lua([[
        WeakTable = setmetatable({}, { __mode = "k" })

        OnceCount = 0

        MyVal = {}
        WeakTable[MyVal] = true

        vim.api.nvim_create_autocmd("FileType", {
          pattern = "*",
          callback = function()
            OnceCount = OnceCount + 1
            MyVal = {}
          end,
          once = true
        })
      ]])

      command [[set filetype=txt]]
      eq(1, exec_lua([[return OnceCount]], {}))

      exec_lua([[collectgarbage()]], {})

      command [[set filetype=txt]]
      eq(1, exec_lua([[return OnceCount]], {}))

      eq(0, exec_lua([[
        local count = 0
        for _ in pairs(WeakTable) do
          count = count + 1
        end

        return count
      ]]), "Should have no keys remaining")
    end)

    it('groups can be cleared', function()
      local augroup = "TestGroup"
      meths.create_augroup(augroup, { clear = true })
      meths.create_autocmd("FileType", {
        group = augroup,
        command = "let g:executed = g:executed + 1"
      })

      set_ft("txt")
      set_ft("txt")
      eq(2, get_executed_count(), "should only count twice")

      meths.create_augroup(augroup, { clear = true })
      eq({}, meths.get_autocmds { group = augroup })

      set_ft("txt")
      set_ft("txt")
      eq(2, get_executed_count(), "No additional counts")
    end)

    it('groups work with once', function()
      local augroup = "TestGroup"

      meths.create_augroup(augroup, { clear = true })
      make_counting_autocmd { group = augroup, once = true }

      set_ft("txt")
      set_ft("python")

      eq(get_executed_count(), 1)
    end)

    it('autocmds can be registered multiple times.', function()
      local augroup = "TestGroup"

      meths.create_augroup(augroup, { clear = true })
      make_counting_autocmd { group = augroup, once = false }
      make_counting_autocmd { group = augroup, once = false }
      make_counting_autocmd { group = augroup, once = false }

      set_ft("txt")
      set_ft("python")

      eq(get_executed_count(), 3 * 2)
    end)

    it('can be deleted', function()
      local augroup = "WillBeDeleted"

      meths.create_augroup(augroup, { clear = true })
      meths.create_autocmd({"Filetype"}, {
        pattern = "*",
        command = "echo 'does not matter'",
      })

      -- Clears the augroup from before, which erases the autocmd
      meths.create_augroup(augroup, { clear = true })

      local result = #meths.get_autocmds { group = augroup }

      eq(0, result)
    end)

    it('can be used for buffer local autocmds', function()
      local augroup = "WillBeDeleted"

      meths.set_var("value_set", false)

      meths.create_augroup(augroup, { clear = true })
      meths.create_autocmd("Filetype", {
        pattern = "<buffer>",
        command = "let g:value_set = v:true",
      })

      command "new"
      command "set filetype=python"

      eq(false, meths.get_var("value_set"))
    end)

    it('can accept vimscript functions', function()
      source [[
        let g:vimscript_executed = 0

        function! MyVimscriptFunction() abort
          let g:vimscript_executed = g:vimscript_executed + 1
        endfunction

        call nvim_create_autocmd("FileType", #{
          \ pattern: ["python", "javascript"],
          \ callback: "MyVimscriptFunction",
          \ })

        set filetype=txt
        set filetype=python
        set filetype=txt
        set filetype=javascript
        set filetype=txt
      ]]

      eq(2, meths.get_var("vimscript_executed"))
    end)
  end)

  describe('augroup!', function()
    it('legacy: should clear and not return any autocmds for delete groups', function()
       command('augroup TEMP_A')
       command('    autocmd! BufReadPost *.py :echo "Hello"')
       command('augroup END')

       command('augroup! TEMP_A')

       eq(false, pcall(meths.get_autocmds, { group = 'TEMP_A' }))

       -- For some reason, augroup! doesn't clear the autocmds themselves, which is just wild
       -- but we managed to keep this behavior.
       eq(1, #meths.get_autocmds { event = 'BufReadPost' })
    end)

    it('legacy: remove augroups that have no autocmds', function()
       command('augroup TEMP_AB')
       command('augroup END')

       command('augroup! TEMP_AB')

       eq(false, pcall(meths.get_autocmds, { group = 'TEMP_AB' }))
       eq(0, #meths.get_autocmds { event = 'BufReadPost' })
    end)

    it('legacy: multiple remove and add augroup', function()
       command('augroup TEMP_ABC')
       command('    au!')
       command('    autocmd BufReadPost *.py echo "Hello"')
       command('augroup END')

       command('augroup! TEMP_ABC')

       -- Should still have one autocmd :'(
       local aus = meths.get_autocmds { event = 'BufReadPost' }
       eq(1, #aus, aus)

       command('augroup TEMP_ABC')
       command('    au!')
       command('    autocmd BufReadPost *.py echo "Hello"')
       command('augroup END')

       -- Should now have two autocmds :'(
       aus = meths.get_autocmds { event = 'BufReadPost' }
       eq(2, #aus, aus)

       command('augroup! TEMP_ABC')

       eq(false, pcall(meths.get_autocmds, { group = 'TEMP_ABC' }))
       eq(2, #meths.get_autocmds { event = 'BufReadPost' })
    end)

    it('api: should clear and not return any autocmds for delete groups by id', function()
       command('augroup TEMP_ABCD')
       command('autocmd! BufReadPost *.py :echo "Hello"')
       command('augroup END')

       local augroup_id = meths.create_augroup("TEMP_ABCD", { clear = false })
       meths.del_augroup_by_id(augroup_id)

       -- For good reason, we kill all the autocmds from del_augroup,
       -- so now this works as expected
       eq(false, pcall(meths.get_autocmds, { group = 'TEMP_ABCD' }))
       eq(0, #meths.get_autocmds { event = 'BufReadPost' })
    end)

    it('api: should clear and not return any autocmds for delete groups by name', function()
       command('augroup TEMP_ABCDE')
       command('autocmd! BufReadPost *.py :echo "Hello"')
       command('augroup END')

       meths.del_augroup_by_name("TEMP_ABCDE")

       -- For good reason, we kill all the autocmds from del_augroup,
       -- so now this works as expected
       eq(false, pcall(meths.get_autocmds, { group = 'TEMP_ABCDE' }))
       eq(0, #meths.get_autocmds { event = 'BufReadPost' })
    end)
  end)
end)
