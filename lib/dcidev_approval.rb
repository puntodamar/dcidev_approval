# frozen_string_literal: true

module DcidevApproval
  def self.included(base)
    base.send :include, InstanceMethods
    base.extend ClassMethods
  end

  module InstanceMethods
    def changes_present?(changes)
      present = false
      changes.each do |k, v|
        if eval("self.#{k}") != v
          present = true
          break
        end
      rescue StandardError => _e
      end
      present
    end

    def waiting_approval?
      %w[pending_update pending_delete].include?(change_status) || status == 'waiting'
    end

    def pending_insert?
      change_status.nil? && %w[waiting rejected].include?(status)
    end

    def pending_update?
      change_status == 'pending_update'
    end

    def pending_delete?
      change_status == 'pending_delete'
    end

    def approved?
      status == 'approved' || change_status.nil?
    end

    def rejected?
      status == 'rejected'
    end

    def waiting?
      status == 'waiting'
    end

    def last_modified_by
      # p self.audit_trail
      log = activity_logs.where(activity_type: %w[update delete]).limit(1).order(created_at: :desc).try(:first)
      {
        modified_by: log.present? ? log.try(:agent).try(:name).to_s + " (#{log.try(:agent).try(:username)} | #{log.try(:agent).try(:roles).try(:first).try(:name)})" : nil,
        modified_at: log.present? ? log.try(:created_at) || try(:updated_at) || try(:created_at) : nil
      }
    end

    def created_by
      log = activity_logs.order(created_at: :desc).limit(1).try(:first)
      {
        created_by: log.present? && log.try(:agent).try(:name).present? ? log.try(:agent).try(:name).to_s + " (#{log.try(:agent_role).try(:name)})" : 'System',
        created_at: try(:created_at) || log.try(:created_at)
      }
    end

    def last_approved_by
      last_approve = activity_logs.where(activity_type: 'approve').limit(1).order(created_at: :desc).try(:first)
      last_entry = activity_logs.limit(1).order(created_at: :desc).try(:first)
      {
        approved_by: last_approve.try(:id) == last_entry.try(:id) ? last_approve.try(:agent).try(:name).to_s + " (#{last_approve.try(:agent_role).try(:name)})" : nil,
        approved_at: last_approve.try(:id) == last_entry.try(:id) ? last_approve.try(:created_at) : nil
      }
    end

    def approve_changes
      if change_status.nil? && %w[waiting rejected].include?(status) && !update(status: :approved, data_changes: nil, change_status: nil)
        raise errors.full_messages.join(', ')
        # ActivityLog.write("Approve insert to #{self.class.to_s}", request, agent, menu, self) if params.log
        # self.delay(queue: "reorder_#{self.id}", priority: 0).reorder if self.class.column_names.include?("view_order")

      end

      case change_status
      when 'pending_update'
        raise errors.full_messages.join(', ') unless update_by_params(data_changes, false)
        raise errors.full_messages.join(', ') unless update(status: :approved, data_changes: nil, change_status: nil)
      # ActivityLog.write("Approve update to #{self.class.to_s}", request, agent, menu, self) if params.log
      # self.delay(queue: "reorder_#{self.id}", priority: 0).reorder if self.class.column_names.include?("view_order")

      when 'pending_delete'
        destroy
      end
    end

    def delete_changes
      # return unless %w[pending_update pending_delete].include? self.change_status
      raise errors.full_messages.join(', ') unless update(data_changes: nil, change_status: nil, status: status == 'waiting' ? :rejected : :approved)
      # ActivityLog.write("Reject changes to #{self.class.to_s}", request, agent, menu, self) if params.log
    end

    def edit_data(params, agent, bypass = true)
      raise 'data still waiting for approval' if waiting_approval?

      if bypass
        raise errors.full_messages.join(', ') unless update_by_params(params, false)
      # ActivityLog.write("Edit #{self.class.to_s}", request, agent, menu, self) if params.log
      elsif changes_present?(params)
        ActiveRecord::Base.transaction do
          data = if agent.is_admin? || status == 'waiting'
                   params
                 else
                   {
                     change_status: :pending_update, data_changes: agent.is_admin? ? nil : params
                   }
                 end
          raise errors.full_messages.join(', ') unless update_by_params(data, false)
        end
        # ActivityLog.write("#{agent.is_admin? ? nil : "Request "}Edit #{self.class.to_s}", request, agent, menu, self) if params.log
      end
      yield self
    end

    def approval(params)
      case params.status
      when 'approved'
        approve_changes
      when 'rejected'
        delete_changes
      end
      yield self
    end

    def delete_data(agent, bypass = true)
      raise 'data still waiting for approval' if waiting_approval?

      if bypass || agent.is_admin?
        ActiveRecord::Base.transaction do
          # ActivityLog.write("Delete #{self.class.to_s}", request, agent, menu, self) if params.log
          raise errors.full_messages.join(', ') unless destroy
        end
      else
        raise errors.full_messages.join(', ') unless update(change_status: :pending_delete)
        # ActivityLog.write("Request Delete #{self.class.to_s}", request, agent, menu, self) if params.log
      end
      yield true
    end
  end

  module ClassMethods
    def create_data(params, agent, bypass = true)
      if bypass
        ActiveRecord::Base.transaction do
          data = params.merge!({ status: :approved })
          d = new_from_params(data)
          raise d.errors.full_messages.join(', ') unless d.save

          yield d
          # ActivityLog.write("#{agent.is_admin? ? nil : "Request "} Add #{self.to_s}", request, agent, menu, d) if params.log
        end
      else
        d = new_from_params(params)
        d.status = agent.is_admin? ? :approved : :waiting
        raise d.errors.full_messages.join(', ') unless d.save

        yield d
      end
    end
  end
end
