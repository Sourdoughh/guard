module Guard

  # The runner defines is responsable to run all methods defined on each guards.
  #
  class Runner

    def deprecation_warning

    end

    # Runs a Guard-task on all registered guards.
    #
    # @param [Symbol] task the task to run
    #
    # @see self.run_supervised_task
    #
    def run(task)
      scoped_guards do |guard|
        run_supervised_task(guard, task)
      end
    end

    # Runs a Guard-task on all registered guards in a specified scope.
    #
    # @param [Symbol] task the task to run
    # @param [Hash] scope either the guard or the group to run the task on
    #
    # @see self.run_supervised_task
    #
    def run_with_scope(task, scope)
      ::Guard.within_preserved_state do
        scoped_guards(scope) do |guard|
          run_supervised_task(guard, task)
        end
      end
    end

    # Runs the appropriate tasks on all registered guards
    # based on the passed changes.
    #
    # @param [Array<String>] modified the modified paths.
    # @param [Array<String>] added the added paths.
    # @param [Array<String>] removed the removed paths.
    #
    def run_on_changes(modified, added, removed)
      ::Guard.within_preserved_state do
        scoped_guards do |guard|
          unless modified.empty?
            modified_paths = Watcher.match_files(guard, modified)
            run_first_task_found(guard, [:run_on_modifications, :run_on_change], modified_paths)
          end

          unless added.empty?
            added_paths = Watcher.match_files(guard, added)
            run_first_task_found(guard, [:run_on_addtions, :run_on_change], added_paths)
          end

          unless removed.empty?
            removed_paths = Watcher.match_files(guard, removed)
            run_first_task_found(guard, [:run_on_removals, :run_on_deletion], removed_paths)
          end
        end
      end
    end

    # Run a Guard task, but remove the Guard when his work leads to a system failure.
    #
    # When the Group has `:halt_on_fail` disabled, we've to catch `:task_has_failed`
    # here in order to avoid an uncaught throw error.
    #
    # @param [Guard::Guard] guard the Guard to execute
    # @param [Symbol] task the task to run
    # @param [Array] args the arguments for the task
    # @raise [:task_has_failed] when task has failed
    #
    def run_supervised_task(guard, task, *args)
      catch Runner.stopping_symbol_for(guard) do
        guard.hook("#{ task }_begin", *args)
        result = guard.send(task, *args)
        guard.hook("#{ task }_end", result)
        result
      end

    rescue NotImplementedError => ex
      raise ex
    rescue Exception => ex
      UI.error("#{ guard.class.name } failed to achieve its <#{ task.to_s }>, exception was:" +
               "\n#{ ex.class }: #{ ex.message }\n#{ ex.backtrace.join("\n") }")

      ::Guard.guards.delete guard
      UI.info("\n#{ guard.class.name } has just been fired")

      ex
    end

    # Returns the symbol that has to be caught when running a supervised task.
    #
    # @note If a Guard group is being run and it has the `:halt_on_fail`
    #   option set, this method returns :no_catch as it will be caught at the
    #   group level.
    # @see .scoped_guards
    #
    # @param [Guard::Guard] guard the Guard to execute
    #
    # @return [Symbol] the symbol to catch
    #
    def self.stopping_symbol_for(guard)
      return :task_has_failed if guard.group.class != Symbol

      group = ::Guard.groups(guard.group)
      group.options[:halt_on_fail] ? :no_catch : :task_has_failed
    end

    private

    # Tries to run the first implemented task by a given guard
    # from a collection of tasks.
    #
    # @param [Guard::Guard] guard the guard to run the found task on
    # @param [Array<Symbol>] tasks the tasks to run the first among
    # @param [Object] task_param the param to pass to each task
    #
    def run_first_task_found(guard, tasks, task_param)
      enum = tasks.to_enum

      begin
        task = enum.next
        UI.debug "Trying to run #{ guard.class.name }##{ task.to_s } with #{ task_param.inspect }"
        run_supervised_task(guard, task, task_param)
      rescue StopIteration
        # Do nothing
      rescue NotImplementedError
        retry
      end
    end

    # Loop through all groups and run the given task for each Guard.
    #
    # Stop the task run for the all Guards within a group if one Guard
    # throws `:task_has_failed`.
    #
    # @param [Hash] scope an hash with a guard or a group scope
    # @yield the task to run
    #
    def scoped_guards(scope = {})
      if guard = scope[:guard]
        yield(guard)
      else
        groups = scope[:group] ? [scope[:group]] : ::Guard.groups
        groups.each do |group|
          catch :task_has_failed do
            ::Guard.guards(:group => group.name).each do |guard|
              yield(guard)
            end
          end
        end
      end
    end

  end
end
