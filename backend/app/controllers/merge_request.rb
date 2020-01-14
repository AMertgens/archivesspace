class ArchivesSpaceService < Sinatra::Base

  Endpoint.post('/merge_requests/subject')
    .description("Carry out a merge request against Subject records")
    .params(["merge_request",
             JSONModel(:merge_request), "A merge request",
             :body => true])
    .permissions([:merge_subject_record])
    .returns([200, :updated]) \
  do
    target, victims = parse_references(params[:merge_request])

    ensure_type(target, victims, 'subject')

    Subject.get_or_die(target[:id]).assimilate(victims.map {|v| Subject.get_or_die(v[:id])})

    json_response(:status => "OK")
  end

  Endpoint.post('/merge_requests/container_profile')
    .description("Carry out a merge request against Container Profile records")
    .example('shell') do
    <<~SHELL
    curl -H 'Content-Type: application/json' \\
        -H "X-ArchivesSpace-Session: $SESSION" \\
        -d '{"uri": "merge_requests/container_profile", "target": {"ref": "/container_profiles/1" },"victims": [{"ref": "/container_profiles/2"}]}' \\
        "http://localhost:8089/merge_requests/container_profile"
    SHELL
    end
    .example('python') do
    <<~PYTHON
    from asnake.client import ASnakeClient
    client = ASnakeClient()
    client.authorize()
    client.post('/merge_requests/container_profile',
            json={
                'uri': 'merge_requests/container_profile',
                'target': {
                    'ref': '/container_profiles/1'
                  },
                'victims': [
                    {
                        'ref': '/container_profiles/2'
                    }
                  ]
                }
          )
    PYTHON
    end
    .params(["merge_request",
             JSONModel(:merge_request), "A merge request",
             :body => true])
    .permissions([:update_container_profile_record])
    .returns([200, :updated]) \
  do
    target, victims = parse_references(params[:merge_request])

    ensure_type(target, victims, 'container_profile')

    ContainerProfile.get_or_die(target[:id]).assimilate(victims.map {|v| ContainerProfile.get_or_die(v[:id])})

    json_response(:status => "OK")
  end

  Endpoint.post('/merge_requests/agent')
    .description("Carry out a merge request against Agent records")
    .params(["merge_request",
             JSONModel(:merge_request), "A merge request",
             :body => true])
    .permissions([:merge_agent_record])
    .returns([200, :updated]) \
  do
    target, victims = parse_references(params[:merge_request])

    if (victims.map {|r| r[:type]} + [target[:type]]).any? {|type| !AgentManager.known_agent_type?(type)}
      raise BadParamsException.new(:merge_request => ["Agent merge request can only merge agent records"])
    end

    agent_model = AgentManager.model_for(target[:type])
    agent_model.get_or_die(target[:id]).assimilate(victims.map {|v|
                                                     AgentManager.model_for(v[:type]).get_or_die(v[:id])
                                                   })

    json_response(:status => "OK")
  end

  Endpoint.post('/merge_requests/agent_detail')
  .description("Carry out a detailed merge request against Agent records")
  .params(["dry_run", BooleanParam, "If true, don't process the merge, just display the merged record", :optional => true],
          ["merge_request_detail",
             JSONModel(:merge_request_detail), "A detailed merge request",
             :body => true])
  .permissions([:merge_agent_record])
  .returns([200, :updated]) \
  do
    STDERR.puts "++++++++++++++++++++++++++++++"
    STDERR.puts "IN BACKEND CONTROLLER"
    STDERR.puts params.inspect

    target, victims = parse_references(params[:merge_request_detail])
    selections = parse_selections(params[:merge_request_detail].selections)

    STDERR.puts selections.inspect

    if (victims.map {|r| r[:type]} + [target[:type]]).any? {|type| !AgentManager.known_agent_type?(type)}
      raise BadParamsException.new(:merge_request_detail => ["Agent merge request can only merge agent records"])
    end
    agent_model = AgentManager.model_for(target[:type])
    target = agent_model.get_or_die(target[:id])
    victim = agent_model.get_or_die(victims[0][:id])
    if params[:dry_run]
      target = agent_model.to_jsonmodel(target)
      victim = agent_model.to_jsonmodel(victim)
      new_target = merge_details(target, victim, selections, true)
      result = new_target
    else
      target_json = agent_model.to_jsonmodel(target)
      victim_json = agent_model.to_jsonmodel(victim)
      new_target = merge_details(target_json, victim_json, selections, false)
      target.assimilate((victims.map {|v|
                                       AgentManager.model_for(v[:type]).get_or_die(v[:id])
                                     }))
      if selections != {}
        target.update_from_json(new_target)
      end
      json_response(:status => "OK")
    end
    json_response(resolve_references(result, ['related_agents']))
  end

  Endpoint.post('/merge_requests/resource')
    .description("Carry out a merge request against Resource records")
    .params(["repo_id", :repo_id],
            ["merge_request",
             JSONModel(:merge_request), "A merge request",
             :body => true])
    .permissions([:merge_archival_record])
    .returns([200, :updated]) \
  do
    target, victims = parse_references(params[:merge_request])
    repo_uri = JSONModel(:repository).uri_for(params[:repo_id])

    check_repository(target, victims, params[:repo_id])
    ensure_type(target, victims, 'resource')

    Resource.get_or_die(target[:id]).assimilate(victims.map {|v| Resource.get_or_die(v[:id])})

    json_response(:status => "OK")
  end


  Endpoint.post('/merge_requests/digital_object')
    .description("Carry out a merge request against Digital_Object records")
    .params(["repo_id", :repo_id],
            ["merge_request",
             JSONModel(:merge_request), "A merge request",
             :body => true])
    .permissions([:merge_archival_record])
    .returns([200, :updated]) \
  do
    target, victims = parse_references(params[:merge_request])
    repo_uri = JSONModel(:repository).uri_for(params[:repo_id])

    check_repository(target, victims, params[:repo_id])
    ensure_type(target, victims, 'digital_object')

    DigitalObject.get_or_die(target[:id]).assimilate(victims.map {|v| DigitalObject.get_or_die(v[:id])})

    json_response(:status => "OK")
  end


  private

  def parse_references(request)
    target = JSONModel.parse_reference(request.target['ref'])
    victims = request.victims.map {|victim| JSONModel.parse_reference(victim['ref'])}

    [target, victims]
  end

  def check_repository(target, victims, repo_id)
    repo_uri = JSONModel(:repository).uri_for(repo_id)

    if ([target] + victims).any? {|r| r[:repository] != repo_uri}
      raise BadParamsException.new(:merge_request => ["All records to merge must be in the repository specified"])
    end
  end


  def ensure_type(target, victims, type)
    if (victims.map {|r| r[:type]} + [target[:type]]).any? {|t| t != type}
      raise BadParamsException.new(:merge_request => ["This merge request can only merge #{type} records"])
    end
  end

  def parse_selections(selections, path=[], all_values={})
    selections.each_pair do |k, v|
      path << k
      case v
        when String
          if v === "REPLACE"
            all_values.merge!({"#{path.join(".")}" => "#{v}"})
            path.pop
          else
            path.pop
            next
          end
        when Hash then parse_selections(v, path, all_values)
        when Array then v.each_with_index do |v2, index|
          path << index
          parse_selections(v2, path, all_values)
        end
        path.pop
        else
          path.pop
          next
      end
    end
    path.pop
    return all_values
  end

  # when merging, set the agent id foreign key (e.g, agent_person_id, agent_family_id...) from the victim to the target
  def set_agent_id(target, victim, subrec, ind)
    if victim[subrec][ind]['agent_person_id']
      victim[subrec][ind]['agent_person_id'] = target['id']

    elsif victim[subrec][ind]['agent_family_id']
      victim[subrec][ind]['agent_family_id'] = target['id']

    elsif victim[subrec][ind]['agent_corporate_entity_id']
      victim[subrec][ind]['agent_corporate_entity_id'] = target['id']

    elsif victim[subrec][ind]['agent_software_id']
      victim[subrec][ind]['agent_software_id'] = target['id']

    # this section updates related_agents ids
    elsif victim[subrec][ind]['agent_person_id_0']
      victim[subrec][ind]['agent_person_id_0'] = target['id']
      
    elsif victim[subrec][ind]['agent_family_id_0']
      victim[subrec][ind]['agent_family_id_0'] = target['id']

    elsif victim[subrec][ind]['agent_corporate_entity_id_0']
      victim[subrec][ind]['agent_corporate_entity_id_0'] = target['id']
    end
    
  end

  def merge_details(target, victim, selections, dry_run)
    STDERR.puts "IN MERGE DETAILS"
    STDERR.puts "target: " + target.inspect
    STDERR.puts "victim: " + victim.inspect
    STDERR.puts "selections: " + selections.inspect


    target[:linked_events] = []
    victim[:linked_events] = []
    selections.each_key do |key|
      path = key.split(".")
      path_fix = []
      path.each do |part|
        if part.length === 1
          part = part.to_i
        elsif (part.length === 2) and (part.start_with?('1'))
          part = part.to_i
        end
        path_fix.push(part)
      end
      path_fix_length = path_fix.length

      # This if statement skips replace for the following types
      if path_fix[0] != 'agent_record_identifiers' &&
         path_fix[0] != 'agent_record_controls' &&
         path_fix[0] != 'agent_other_agency_codes' &&
         path_fix[0] != 'agent_conventions_declarations' &&
         path_fix[0] != 'agent_maintenance_histories' &&
         path_fix[0] != 'agent_sources' &&
         path_fix[0] != 'agent_alternate_sets' &&
         path_fix[0] != 'agent_identifiers' &&
         path_fix[0] != 'names' &&
         path_fix[0] != 'dates_of_existence' &&
         path_fix[0] != 'agent_genders' &&
         path_fix[0] != 'agent_places' &&
         path_fix[0] != 'agent_occupations' &&
         path_fix[0] != 'agent_functions' &&
         path_fix[0] != 'agent_topics' &&
         path_fix[0] != 'used_languages' &&
         path_fix[0] != 'agent_contacts' &&
         path_fix[0] != 'notes' && 
         path_fix[0] != 'external_documents' && 
         path_fix[0] != 'agent_resources' && 
         path_fix[0] != 'related_agents' 
        # REPLACE code
        case path_fix_length
          when 1
            target[path_fix[0]] = victim[path_fix[0]]
          when 2
            target[path_fix[0]][path_fix[1]] = victim[path_fix[0]][path_fix[1]]
          when 3
            begin
              if target[path_fix[0]].length <= path_fix[1]
                target[path_fix[0]].push(victim[path_fix[0]][path_fix[1]])
              end
              target[path_fix[0]][path_fix[1]][path_fix[2]] = victim[path_fix[0]][path_fix[1]][path_fix[2]]
            rescue
              if target[path_fix[0]] === []
                target[path_fix[0]].push(victim[path_fix[0]][path_fix[1]])
              end
            end
          when 4
            target[path_fix[0]][path_fix[1]][path_fix[2]][path_fix[3]] = victim[path_fix[0]][path_fix[1]][path_fix[2]][path_fix[3]]
          when 5
            begin
              target[path_fix[0]][path_fix[1]][path_fix[2]][path_fix[3]][path_fix[4]] = victim[path_fix[0]][path_fix[1]][path_fix[2]][path_fix[3]][path_fix[4]]
            rescue
              if target[path_fix[0]] === []
                target[path_fix[0]].push(victim[path_fix[0]][path_fix[1]])
              elsif target[path_fix[0]][path_fix[1]][path_fix[2]] === []
                target[path_fix[0]][path_fix[1]][path_fix[2]].push(victim[path_fix[0]][path_fix[1]][path_fix[2]][path_fix[3]])
              end
            end
        end
      # This code runs subrecord ADD
      elsif path_fix[0] === 'agent_record_identifiers'
        set_agent_id(target, victim, 'agent_record_identifiers', path_fix[1])

        target['agent_record_identifiers'].push(victim['agent_record_identifiers'][path_fix[1]])

      elsif path_fix[0] === 'agent_record_controls'
        set_agent_id(target, victim, 'agent_record_controls', path_fix[1])

        target['agent_record_controls'].push(victim['agent_record_controls'][path_fix[1]])

      elsif path_fix[0] === 'agent_other_agency_codes'
        set_agent_id(target, victim, 'agent_other_agency_codes', path_fix[1])

        target['agent_other_agency_codes'].push(victim['agent_other_agency_codes'][path_fix[1]])

      elsif path_fix[0] === 'agent_conventions_declarations'
        set_agent_id(target, victim, 'agent_conventions_declarations', path_fix[1])

        target['agent_conventions_declarations'].push(victim['agent_conventions_declarations'][path_fix[1]])

      elsif path_fix[0] === 'agent_maintenance_histories'
        set_agent_id(target, victim, 'agent_maintenance_histories', path_fix[1])

        target['agent_maintenance_histories'].push(victim['agent_maintenance_histories'][path_fix[1]])

      elsif path_fix[0] === 'agent_sources'
        set_agent_id(target, victim, 'agent_sources', path_fix[1])

        target['agent_sources'].push(victim['agent_sources'][path_fix[1]])

      elsif path_fix[0] === 'agent_alternate_sets'
        set_agent_id(target, victim, 'agent_alternate_sets', path_fix[1])

        target['agent_alternate_sets'].push(victim['agent_alternate_sets'][path_fix[1]])

      elsif path_fix[0] === 'agent_identifiers'
        set_agent_id(target, victim, 'agent_identifiers', path_fix[1])

        target['agent_identifiers'].push(victim['agent_identifiers'][path_fix[1]])

      elsif path_fix[0] === 'names'
        set_agent_id(target, victim, 'names', path_fix[1])

        # an agent can only have one authorized or display name.
        # make sure the name being merged in doesn't conflict with this
        victim['names'][path_fix[1]]['authorized'] = false
        victim['names'][path_fix[1]]['is_display_name'] = false

        target['names'].push(victim['names'][path_fix[1]])

      elsif path_fix[0] === 'dates_of_existence'
        set_agent_id(target, victim, 'dates_of_existence', path_fix[1])

        target['dates_of_existence'].push(victim['dates_of_existence'][path_fix[1]])

      elsif path_fix[0] === 'agent_genders'
        set_agent_id(target, victim, 'agent_genders', path_fix[1])

        target['agent_genders'].push(victim['agent_genders'][path_fix[1]])

      elsif path_fix[0] === 'agent_places'
        set_agent_id(target, victim, 'agent_places', path_fix[1])

        target['agent_places'].push(victim['agent_places'][path_fix[1]])

      elsif path_fix[0] === 'agent_occupations'
        set_agent_id(target, victim, 'agent_occupations', path_fix[1])

        target['agent_occupations'].push(victim['agent_occupations'][path_fix[1]])

      elsif path_fix[0] === 'agent_functions'
        set_agent_id(target, victim, 'agent_functions', path_fix[1])

        target['agent_functions'].push(victim['agent_functions'][path_fix[1]])

      elsif path_fix[0] === 'agent_topics'
        set_agent_id(target, victim, 'agent_topics', path_fix[1])

        target['agent_topics'].push(victim['agent_topics'][path_fix[1]])

      elsif path_fix[0] === 'used_languages'
        set_agent_id(target, victim, 'used_languages', path_fix[1])

        target['used_languages'].push(victim['used_languages'][path_fix[1]])

      elsif path_fix[0] === 'agent_contacts'
        set_agent_id(target, victim, 'agent_contacts', path_fix[1])

        target['agent_contacts'].push(victim['agent_contacts'][path_fix[1]])

      elsif path_fix[0] === 'notes'
        set_agent_id(target, victim, 'notes', path_fix[1])

        target['notes'].push(victim['notes'][path_fix[1]])

      elsif path_fix[0] === 'external_documents'
        set_agent_id(target, victim, 'external_documents', path_fix[1])

        target['external_documents'].push(victim['external_documents'][path_fix[1]])

      elsif path_fix[0] === 'agent_resources'
        set_agent_id(target, victim, 'agent_resources', path_fix[1])

        target['agent_resources'].push(victim['agent_resources'][path_fix[1]])

      elsif path_fix[0] === 'related_agents'
        set_agent_id(target, victim, 'related_agents', path_fix[1])

        target['related_agents'].push(victim['related_agents'][path_fix[1]])
      end

      target['title'] = target['names'][0]['sort_name']
    end
    if dry_run == true
      target['title'] = preview_sort_name(target['names'][0])
      target['names'][0]['sort_name'] = target['title']
      target['related_agents'] = (target['related_agents'] + victim['related_agents']).uniq
    end
    target
  end

  # NOTE: this code is a duplicate of the auto_generate code for creating sort name
  # in the name_person, name_family, name_software, name_corporate_entity models
  # Consider refactoring when continued work done on the agents model enhancements
  def preview_sort_name(target)
    result = ""

    case target['jsonmodel_type']
    when 'name_person'
      if target["name_order"] === "inverted"
        result << target["primary_name"] if target["primary_name"]
        result << ", #{target["rest_of_name"]}" if target["rest_of_name"]
      elsif target["name_order"] === "direct"
        result << target["rest_of_name"] if target["rest_of_name"]
        result << " #{target["primary_name"]}" if target["primary_name"]
      else
        result << target["primary_name"] if target["primary_name"]
      end

      result << ", #{target["prefix"]}" if target["prefix"]
      result << ", #{target["suffix"]}" if target["suffix"]
      result << ", #{target["title"]}" if target["title"]
      result << ", #{target["number"]}" if target["number"]
      result << " (#{target["fuller_form"]})" if target["fuller_form"]
      result << ", #{target["dates"]}" if target["dates"]
    when 'name_corporate_entity'
      result << "#{target["primary_name"]}" if target["primary_name"]
      result << ". #{target["subordinate_name_1"]}" if target["subordinate_name_1"]
      result << ". #{target["subordinate_name_2"]}" if target["subordinate_name_2"]

      grouped = [target["number"], target["dates"]].reject{|v| v.nil?}
      result << " (#{grouped.join(" : ")})" if not grouped.empty?
    when 'name_family'
      result << target["family_name"] if target["family_name"]
      result << ", #{target["prefix"]}" if target["prefix"]
      result << ", #{target["dates"]}" if target["dates"]
    when 'name_software'
      result << "#{target["manufacturer"]} " if target["manufacturer"]
      result << "#{target["software_name"]}" if target["software_name"]
      result << " #{target["version"]}" if target["version"]
    end

    result << " (#{target["qualifier"]})" if target["qualifier"]

    result.lstrip!

    if result.length > 255
      return result[0..254]
    else
      return result
    end

  end
end
