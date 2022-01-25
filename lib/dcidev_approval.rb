module DcidevApproval
  def self.included base
    base.send :include, InstanceMethods
    base.extend ClassMethods
  end

  module InstanceMethods

    def changes_present?(changes)
      present = false
      changes.each do |k, v|
        begin
          if eval("self.#{k}") != v
            present = true
            break
          end
        rescue => _
        end
      end
      return present
    end

    def waiting_approval?
      %w[pending_update pending_delete].include?(self.change_status) || self.status == "waiting"
    end

    def pending_insert?
      self.change_status.nil? && %w[waiting rejected].include?(self.status)
    end

    def pending_update?
      self.change_status == "pending_update"
    end

    def pending_delete?
      self.change_status == "pending_delete"
    end

    def last_modified_by
      # p self.audit_trail
      if self.try(:change_status).present? && self.try(:change_status) == 'pending_delete'
        log = self.activity_logs.where("activity LIKE '%delete%'").limit(1).order(created_at: :desc).try(:first)
      else
        log = self.activity_logs.where("activity LIKE '%edit%'").limit(1).order(created_at: :desc).try(:first)
      end
      {
        modified_by: log.present? ? log.try(:agent).try(:name).to_s + " (#{log.try(:agent).try(:username).to_s}[#{log.try(:agent).try(:roles).try(:first).try(:name)}])" : "System",
        modified_at: log.present? ? log.try(:created_at) || self.try(:updated_at) || self.try(:created_at) : nil
      }
    end

    def created_by
      log = self.activity_logs.try(:first)
      {
        created_by: log.present? && log.try(:agent).try(:name).present? ? log.try(:agent).try(:name).to_s + " (#{log.try(:agent).try(:username).to_s}[#{log.try(:agent).try(:roles).try(:first).try(:name)}])" : "System",
        created_at: self.try(:created_at) || log.try(:created_at)
      }
    end

    def last_approved_by
      last_approve = self.activity_logs.where("activity LIKE '%approv%'").limit(1).order(created_at: :desc).try(:first)
      last_entry = self.activity_logs.last
      {
        approved_by: last_approve.try(:id) == last_entry.try(:id) ? last_approve.try(:agent).try(:name) : nil,
        approved_at: last_approve.try(:id) == last_entry.try(:id) ? last_approve.try(:created_at) : nil
      }
    end

    def approve_changes

      if self.change_status.nil? && %w[waiting rejected].include?(self.status)
        raise self.errors.full_messages.join(", ") unless self.update(status: :approved, data_changes: nil, change_status: nil)
        # ActivityLog.write("Approve insert to #{self.class.to_s}", request, agent, menu, self) if params.log
        # self.delay(queue: "reorder_#{self.id}", priority: 0).reorder if self.class.column_names.include?("view_order")

      end
      if self.change_status == "pending_update"
        raise self.errors.full_messages.join(", ") unless self.update_by_params(self.data_changes, false)
        raise self.errors.full_messages.join(", ") unless self.update(status: :approved, data_changes: nil, change_status: nil)
        # ActivityLog.write("Approve update to #{self.class.to_s}", request, agent, menu, self) if params.log
        # self.delay(queue: "reorder_#{self.id}", priority: 0).reorder if self.class.column_names.include?("view_order")

      elsif self.change_status == "pending_delete"
        raise self.errors.full_messages.join(", ") unless self.update(change_status: nil, data_changes: nil)
        ActiveRecord::Base.transaction do
          # ActivityLog.write("Approve delete to #{self.class.to_s}", request, agent, menu, self) if params.log
          self.try(:destroy)
        end
      end
    end

    def delete_changes
      # return unless %w[pending_update pending_delete].include? self.change_status
      raise self.errors.full_messages.join(", ") unless self.update(data_changes: nil, change_status: nil, status: self.status == "waiting" ? :rejected : :approved)
      # ActivityLog.write("Reject changes to #{self.class.to_s}", request, agent, menu, self) if params.log
    end

    def edit_data(params, agent, bypass = true)
      raise "data still waiting for approval" if self.waiting_approval?
      if bypass
        raise self.errors.full_messages.join(", ") unless self.update_by_params(params, false)
        # ActivityLog.write("Edit #{self.class.to_s}", request, agent, menu, self) if params.log
      else
        if self.changes_present?(params)
          ActiveRecord::Base.transaction do
            data = (agent.is_admin? || self.status == "waiting") ? params : { change_status: :pending_update, data_changes: agent.is_admin? ? nil : params }
            raise self.errors.full_messages.join(", ") unless self.update_by_params(data, false)
          end
          # ActivityLog.write("#{agent.is_admin? ? nil : "Request "}Edit #{self.class.to_s}", request, agent, menu, self) if params.log
        end
      end
      yield true
    end

    def approval(params)
      if params.status == "approved"
        self.approve_changes
      elsif params.status == "rejected"
        self.delete_changes
      end
      yield true
    end

    def delete_data(agent, bypass = true)
      raise "data still waiting for approval" if self.waiting_approval?
      if bypass || agent.is_admin?
        ActiveRecord::Base.transaction do
          # ActivityLog.write("Delete #{self.class.to_s}", request, agent, menu, self) if params.log
          raise self.errors.full_messages.join(", ") unless self.destroy
        end
      else
        raise self.errors.full_messages.join(", ") unless self.update(change_status: :pending_delete)
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
          d = self.new_from_params(data)
          raise d.errors.full_messages.join(", ") unless d.save
          # ActivityLog.write("#{agent.is_admin? ? nil : "Request "} Add #{self.to_s}", request, agent, menu, d) if params.log
        end
      else
        d = self.new_from_params(params)
        d.status = agent.is_admin? ? :approved : :waiting
        raise d.errors.full_messages.join(", ") unless d.save
        # ActivityLog.write("Add #{self.to_s}", request, agent, menu, d) if params.log
      end
      yield d
    end
  end
end

