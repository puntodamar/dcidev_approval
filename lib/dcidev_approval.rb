module DcidevApproval
  class << self
    def included base
      base.send :include, InstanceMethods
      base.extend ClassMethods
    end
  end

  module ClassMethods
    def do_stuff(a, b, c, callback)
      sum = a + b + c
      callback.call(a, b, c, sum)
    end
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

    def audit_trail
      self.audit_trail.order(created_at: :desc)
    end

    def last_modified_by
      # p self.audit_trail
      if self.try(:change_status).present? && self.try(:change_status) == 'pending_delete'
        log = self.activity_logs.delete_data.limit(1).order(created_at: :desc).try(:first)
      else
        log = self.activity_logs.edit_data.limit(1).order(created_at: :desc).try(:first)
      end
      {
        modified_by: log.present? ? log.try(:agent).try(:name).to_s + " (#{log.try(:agent).try(:username).to_s}[#{log.try(:agent).try(:roles).try(:first).try(:name)}])" : "System",
        modified_at: log.try(:created_at) || self.try(:updated_at) || self.try(:created_at)
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
      last_approve = self.activity_logs.approve_data.limit(1).order(created_at: :desc).try(:first)
      last_entry = self.activity_logs.last
      {
        approved_by: last_approve.try(:id) == last_entry.try(:id) ? last_approve.try(:agent).try(:name) : nil,
        approved_at: last_approve.try(:id) == last_entry.try(:id) ? last_approve.try(:created_at) : nil
      }
    end
  end

end

