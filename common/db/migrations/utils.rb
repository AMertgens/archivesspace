Sequel.extension :inflector

module MigrationUtils
  def self.shorten_table(name)
    name.to_s.split("_").map {|s| s[0...3]}.join("_")
  end
end


def create_editable_enum(name, values, default = nil, opts = {})
      create_enum(name, values, default, true, opts)
    end


def create_enum(name, values, default = nil, editable = false, opts = {})
  id = self[:enumeration].insert(:name => name,
                                 :json_schema_version => 1,
                                 :editable => editable ? 1 : 0,
                                 :create_time => Time.now,
                                 :system_mtime => Time.now,
                                 :user_mtime => Time.now)
  
  id_of_default = nil
  
  readonly_values = Array(opts[:readonly_values])
  
  values.each do |value|
    id_of_value = self[:enumeration_value].insert(:enumeration_id => id, :value => value,
                                                  :readonly => readonly_values.include?(value) ? 1 : 0)
    id_of_default = id_of_value if value === default
  end
  
  if !id_of_default.nil?
    self[:enumeration].where(:id => id).update(:default_value => id_of_default)
  end
end
