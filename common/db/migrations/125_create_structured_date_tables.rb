require_relative 'utils'

Sequel.migration do

  up do
    create_enum("date_type_enum", ["single", "range"])
    create_enum("date_role_enum", ["begin", "end"])
    create_enum("date_standardized_type_enum", ["standard", "not_before", "not_after"])
    create_enum("begin_date_standardized_type_enum", ["standard", "not_before", "not_after"])
    create_enum("end_date_standardized_type_enum", ["standard", "not_before", "not_after"])

    date_std_type_id = get_enum_value_id("date_standardized_type_enum", "standard")

    create_table(:structured_date_single) do
      primary_key :id
      Integer :structured_date_label_id, :null => false

      Integer :date_role_enum_id, :null => false
      String :date_expression, :null => true
      String :date_standardized, :null => true
      Integer :date_standardized_type_enum_id, :null => false, :default => date_std_type_id

      apply_mtime_columns
      Integer :lock_version, :default => 0, :null => false
    end

    create_table(:structured_date_range) do
      primary_key :id
      Integer :structured_date_label_id, :null => false

      String :begin_date_expression, :null => true
      String :begin_date_standardized, :null => true
      Integer :begin_date_standardized_type_enum_id, :null => false, :default => date_std_type_id

      String :end_date_expression, :null => true
      String :end_date_standardized, :null => true
      Integer :end_date_standardized_type_enum_id, :null => false, :default => date_std_type_id

      apply_mtime_columns
      Integer :lock_version, :default => 0, :null => false
    end

    create_table(:structured_date_label) do
      primary_key :id

      Integer :date_label_id, :null => false # existing enum date_label
      Integer :date_type_enum_id, :null => false
      Integer :date_certainty_id, :null => true # existing enum date_certainty
      Integer :date_era_id, :null => true # existing enum date_era
      Integer :date_calendar_id, :null => true # existing enum date_calendar

      apply_mtime_columns
      Integer :lock_version, :default => 0, :null => false
    end

  end

end