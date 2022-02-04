# Setup
##### 1. Add new column named `status` to every model requiring this gem
`db/migrate/migration_file.rb`
```ruby
class AddStatusToProduk < ActiveRecord::Migration[6.0]
    def change 
        add_column :produk, :status, :string
        add_column :produk, :change_status, :string
    end
end
```
`app/models/model.rb`
```ruby
STATUS = %w[waiting approved rejected].freeze
enum status: STATUS.zip(STATUS).to_h, _prefix: true

CHANGE_STATUS = %w(pending_delete pending_update).freeze
enum change_status: CHANGE_STATUS.zip(CHANGE_STATUS).to_h, _prefix: true
```



##### 2. Format your `Agent` and `Role` with one-many relationship.
##### 3.  Declare instance method `is_admin?` to `Agent` to find out whether an agent is an admin or not

```ruby
def is_admin?
    # add your custom logic here
    self.approved? && ["admin", "super_admin", "checker"].include?(self.try(:roles).try(:first).try(:code))
end
```

##### 4. Include the module to every model requiring approval. Or just put it in `ApplicationRecord`
`app/models/application_record.rb`
```ruby
class ApplicationRecord < ActiveRecord::Base
    include DcidevApproval
    self.abstract_class = true
    # ...
end
```

# Features
* Create: `Model.create_data(declared(params), current_user, bypass)`
* Update: `model.edit_data(declared(params), current_user, bypass)`
* Delete: `model.delete_data(declared(params), current_user, bypass)`
* Approval: `model.approval(declared(params))`
* Compare current database value and argument to check if there are any update: `model.changes_present?(params)`
* Check approval status: `model.waiting_approval?`, `model.pending_insert?`, `model.pending_update?`, `model.pending_delete?`
* Find last lodifier & timestamp: `model.last_modified_by`
* Find author: `model.created_by`
* Find approval agent & timestamp: `model.last_approved_by`

Explanation
* `declared(params)`: is a hash value from Grape Parameters, plain ruby hash can also be used
* `current_user`: the agent responsible for the changes
* `bypass`: boolean value to toogle the approval system. If not sent, the default value is `true`

To track changes peformed to a record, call 
# Callbacks
To execute code before/after the CRUD, include module `DcidevApproval` in `ApplicationRecord` and peform overide and or overload on it's child model.

`app/models/application_record.rb`
```ruby
class ApplicationRecord < ActiveRecord::Base
    include DcidevApproval
    self.abstract_class = true
    # ...
end
```

`app/models/child_model.rb`
```ruby
class ChildModel < ApplicationRecord
    # ...
    def self.create_data(params, agent, request)
        super(params, agent, false) do |data|
            # do something after the record is successfully created
            # in this case, write an activity log
            # the data variable will return the created record
            ActivityLog.write("#{agent.is_admin? || params.bypass ? nil : "Request "} Add #{self.class.to_s}", request, agent, menu, data) if params.log
        end
    end
    
    def edit_data(params, agent, request)
        super(params, agent, false) do |_|
            # do something after the record is successfully edited and require approval
        end
    end
    # ...
end

```