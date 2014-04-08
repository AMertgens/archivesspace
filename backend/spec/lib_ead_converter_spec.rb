# -*- coding: utf-8 -*-
require 'spec_helper'
require 'converter_spec_helper'

require_relative '../app/converters/ead_converter'

describe 'EAD converter' do
  let(:my_converter) {
    EADConverter
  }


  let (:test_doc_1) {
    src = <<ANEAD
<c id="1" level="file">
  <unittitle>oh well</unittitle>
  <container id="cid1" type="Box" label="Text">1</container>
  <container parent="cid2" type="Folder"></container>
  <unitdate normal="1907/1911" era="ce" calendar="gregorian" type="inclusive">1907-1911</unitdate>
  <c id="2" level="file">
    <unittitle>whatever</unittitle>
    <container id="cid3" type="Box" label="Text">FOO</container>
  </c>
</c>
ANEAD

    get_tempfile_path(src)
  }


  it "should be able to manage empty tags" do
    converter = EADConverter.new(test_doc_1)
    converter.run
    parsed = JSON(IO.read(converter.get_output_path))

    parsed.length.should eq(2)
    parsed.find{|r| r['ref_id'] == '1'}['instances'][0]['container']['type_2'].should eq('Folder')
  end


  describe "EAD Import Mappings" do
    let(:test_file) {
      File.expand_path("../app/exporters/examples/ead/at-tracer.xml", File.dirname(__FILE__))
    }

    before(:all) do
      parsed = convert(test_file)

      @corps = parsed.select {|rec| rec['jsonmodel_type'] == 'agent_corporate_entity'}
      @families = parsed.select {|rec| rec['jsonmodel_type'] == 'agent_family'}
      @people = parsed.select {|rec| rec['jsonmodel_type'] == 'agent_person'}
      @subjects = parsed.select {|rec| rec['jsonmodel_type'] == 'subject'}
      @digital_objects = parsed.select {|rec| rec['jsonmodel_type'] == 'digital_object'}

      @archival_objects = parsed.select {|rec| rec['jsonmodel_type'] == 'archival_object'}.
                                 inject({}) {|result, a|
        a['title'].match(/C([0-9]{2})/) do |m|
          result[m[1]] = a
        end

        result
      }

      @resource = parsed.select {|rec| rec['jsonmodel_type'] == 'resource'}.last
    end


    it "creates the archival object tree correctly" do
      # check the hierarchy (don't be fooled by the system ids when this test fails - they won't match the keys)
      @archival_objects.each do |k, v|
        if k.to_i > 1
          parent_key = sprintf '%02d', k.to_i - 1
          v['parent']['ref'].should eq(@archival_objects[parent_key]['uri'])
        end
      end
    end

    # SPECIFICATION SOURCE: https://archivesspace.basecamphq.com/F158503515
    # Comments should roughly match column 1 of the spreadsheet

    # Note: Elements should be linked at the appropriate level (e.g. in the context to a Resource or Archival Object record).

    # Source element	Processing / Formatting Directions
    #  @id
    #  @target
    #  @audience	WHEN @audience = internal

    # RESOURCE
    it "maps '<date>' correctly" do
      # 	IF nested in <chronitem>
      get_subnotes_by_type(get_note(@archival_objects['12'], 'ref53'), 'note_chronology')[0]['items'][0]['event_date'].should eq('1895')

      get_subnotes_by_type(get_note(@archival_objects['12'], 'ref53'), 'note_chronology')[0]['items'][1]['event_date'].should eq('1995')

      # 	IF nested in <publicationstmt>
      @resource['finding_aid_date'].should eq('Resource-FindingAidDate-AT')

      # 	ELSE
    end

    it "maps '<extent>' correctly" do
      #  	IF value starts with a number followed by a space and can be parsed
      @resource['extents'][0]['number'].should eq("5.0")
      @resource['extents'][0]['extent_type'].should eq("Linear feet")

      # 	ELSE
      @resource['extents'][0]['container_summary'].should eq("Resource-ContainerSummary-AT")
    end


    it "maps '<unitdate>' correctly" do
      @resource['dates'][0]['expression'].should eq("Bulk, 1960-1970")
      @resource['dates'][0]['date_type'].should eq("inclusive")

      @resource['dates'][1]['expression'].should eq("Resource-Title-AT")
      @resource['dates'][1]['date_type'].should eq("inclusive")
    end

    it "maps '<unitid>' correctly" do
      # 	IF nested in <archdesc><did>
      @resource["id_0"].should eq("Resource.ID.AT")

      # 	IF nested in <c><did>
    end

    it "maps '<unittitle>' correctly" do
      # 	IF nested in <archdesc><did>
      @resource["title"].should eq("Resource--Title-AT")
      # 	IF nested in <c><did>
      @archival_objects['12']['title'].should eq("Resource-C12-AT")
    end


    # FINDING AID ELEMENTS
    it "maps '<author>' correctly" do
      @resource['finding_aid_author'].should eq('Finding aid prepared by Resource-FindingAidAuthor-AT')
    end

    it "maps '<descrules>' correctly" do
      @resource['finding_aid_description_rules'].should eq('Describing Archives: A Content Standard')
    end

    it "maps '<eadid>' correctly" do
      @resource['ead_id'].should eq('Resource-EAD-ID-AT')
    end

    it "maps '<eadid @url>' correctly" do
      @resource['ead_location'].should eq('Resource-EAD-Location-AT')
    end

    it "maps '<editionstmt>' correctly" do
      @resource['finding_aid_edition_statement'].should eq("<p>Resource-FindingAidEdition-AT</p>")
    end

    it "maps '<seriesstmt>' correctly" do
      @resource['finding_aid_series_statement'].should eq("<p>Resource-FindingAidSeries-AT</p>")
    end

    it "maps '<sponsor>' correctly" do
      @resource['finding_aid_sponsor'].should eq('Resource-Sponsor-AT')
    end

    it "maps '<subtitle>' correctly" do
    end

    it "maps '<titleproper>' correctly" do
      @resource['finding_aid_title'].should eq("Resource-FindingAidTitle-AT\n<num>Resource.ID.AT</num>")
    end

    it "maps '<titleproper type=\"filing\">' correctly" do
      @resource['finding_aid_filing_title'].should eq('Resource-FindingAidFilingTitle-AT')
    end

    it "maps '<langusage>' correctly" do
      @resource['finding_aid_language'].should eq('Resource-FindingAidLanguage-AT')
    end

    it "maps '<revisiondesc>' correctly" do
      @resource['finding_aid_revision_description'].should eq("<change>\n<date>Resource-FindingAidRevisionDate-AT</date>\n<item>Resource-FindingAidRevisionDescription-AT</item>\n</change>")
    end

    # NAMES
    it "maps '<corpname>' correctly" do
      # 	IF nested in <origination> OR <controlaccess>
      # 	IF nested in <origination>
      c1 = @corps.find {|corp| corp['names'][0]['primary_name'] == "CNames-PrimaryName-AT. CNames-Subordinate1-AT. CNames-Subordiate2-AT. (CNames-Number-AT) (CNames-Qualifier-AT)"}
      c1.should_not be_nil

      linked = @resource['linked_agents'].find {|a| a['ref'] == c1['uri']}
      linked['role'].should eq('creator')
      # 	IF nested in <controlaccess>
      c2 = @corps.find {|corp| corp['names'][0]['primary_name'] == "CNames-PrimaryName-AT. CNames-Subordinate1-AT. CNames-Subordiate2-AT. (CNames-Number-AT) (CNames-Qualifier-AT) -- Archives"}
      c2.should_not be_nil

      linked = @resource['linked_agents'].find {|a| a['ref'] == c2['uri']}
      linked['role'].should eq('subject')

      # 	ELSE
      # 	IF @rules != NULL ==> name_corporate_entity.rules
      [c1, c2].map {|c| c['names'][0]['rules']}.uniq.should eq(['dacs'])
      # 	IF @source != NULL ==> name_corporate_entity.source
        [c1, c2].map {|c| c['names'][0]['source']}.uniq.should eq(['naf'])
      # 	IF @authfilenumber != NULL
    end

    it "maps '<famname>' correctly" do
      # 	IF nested in <origination> OR <controlaccess>
      uris = @archival_objects['06']['linked_agents'].map {|l| l['ref'] } & @families.map {|f| f['uri'] }
      links = @archival_objects['06']['linked_agents'].select {|l| uris.include?(l['ref']) }
      fams = @families.select {|f| uris.include?(f['uri']) }

      # 	IF nested in <origination>
      n1 = fams.find{|f| f['uri'] == links.find{|l| l['role'] == 'creator' }['ref'] }['names'][0]['family_name']
      n1.should eq("FNames-FamilyName-AT, FNames-Prefix-AT, FNames-Qualifier-AT")
      # 	IF nested in <controlaccess>
      n2 = fams.find{|f| f['uri'] == links.find{|l| l['role'] == 'subject' }['ref'] }['names'][0]['family_name']
      n2.should eq("FNames-FamilyName-AT, FNames-Prefix-AT, FNames-Qualifier-AT -- Pictorial works")
      # 	ELSE
      # 	IF @rules != NULL
      fams.map{|f| f['names'][0]['rules']}.uniq.should eq(['aacr'])
      # 	IF @source != NULL
      fams.map{|f| f['names'][0]['source']}.uniq.should eq(['naf'])
      # 	IF @authfilenumber != NULL
    end

    it "maps '<persname>' correctly" do
      # 	IF nested in <origination> OR <controlaccess>
      # 	IF nested in <origination>
      @archival_objects['01']['linked_agents'].find {|l| @people.map{|p| p['uri'] }.include?(l['ref'])}['role'].should eq('creator')
      # 	IF nested in <controlaccess>
      @archival_objects['06']['linked_agents'].reverse.find {|l| @people.map{|p| p['uri'] }.include?(l['ref'])}['role'].should eq('subject')
      # 	ELSE
      # 	IF @rules != NULL
      @people.map {|p| p['names'][0]['rules']}.uniq.should eq(['local'])
      # 	IF @source != NULL
      @people.map {|p| p['names'][0]['source']}.uniq.should eq(['local'])
      # 	IF @authfilenumber != NULL
    end

      # SUBJECTS
    it "maps '<function>' correctly" do
      # 	IF nested in <controlaccess>
      subject = @subjects.find{|s| s['terms'][0]['term_type'] == 'function'}
        [@resource, @archival_objects["06"], @archival_objects["12"]].each do |a|
        a['subjects'].select{|s| s['ref'] == subject['uri']}.count.should eq(1)
      end
      #   @source
      subject['source'].should eq('local')
      # 	ELSE
      # 	IF @authfilenumber != NULL
    end

    it "maps '<genreform>' correctly" do
      # 	IF nested in <controlaccess>
      subject = @subjects.find{|s| s['terms'][0]['term_type'] == 'genre_form'}
      [@resource, @archival_objects["06"], @archival_objects["12"]].each do |a|
        a['subjects'].select{|s| s['ref'] == subject['uri']}.count.should eq(1)
      end
      #   @source
      subject['source'].should eq('local')
      # 	ELSE
      # 	IF @authfilenumber != NULL
    end

    it "maps '<geogname>' correctly" do
      # 	IF nested in <controlaccess>
      subject = @subjects.find{|s| s['terms'][0]['term_type'] == 'geographic'}
      [@resource, @archival_objects["06"], @archival_objects["12"]].each do |a|
        a['subjects'].select{|s| s['ref'] == subject['uri']}.count.should eq(1)
      end
      #   @source
      subject['source'].should eq('local')
      # 	ELSE
      # 	IF @authfilenumber != NULL
    end

    it "maps '<occupation>' correctly" do
      subject = @subjects.find{|s| s['terms'][0]['term_type'] == 'occupation'}
      [@resource, @archival_objects["06"], @archival_objects["12"]].each do |a|
        a['subjects'].select{|s| s['ref'] == subject['uri']}.count.should eq(1)
      end
      #   @source
      subject['source'].should eq('local')
      # 	ELSE
      # 	IF @authfilenumber != NULL
    end

    it "maps '<subject>' correctly" do
      # 	IF nested in <controlaccess>
      subject = @subjects.find{|s| s['terms'][0]['term_type'] == 'topical'}
        [@resource, @archival_objects["06"], @archival_objects["12"]].each do |a|
        a['subjects'].select{|s| s['ref'] == subject['uri']}.count.should eq(1)
      end
      #   @source
      subject['source'].should eq('local')
      # 	ELSE
      # 	IF @authfilenumber != NULL
    end

      # NOTES
      # if other EAD elements that map to a note object are nested in eachother, then those notes will be treated as separate notes;
      # for example, a <scopecontent> may contain another <scopecontent>, etc.;
      # therefore, if  <scopecontent> tag contains a nested <scopecontent>, the note contents will be mapped into two separate notes of type "Scope and Contents note" in the Toolkit;
      # if, for example, an <accessrestrict> tag contains a nested <legalstatus>, the tag contents will be mapped into separate notes, one of type "accessrestict" and the part tagged as <legalstatus> as type "legalstatus".
      # if one or more <note> tags are nested, then those <note> tags will initiate separate notes with the NoteType equivalent to the parent note.
      # That is, where <accessrestrict> tag contains a nested <note>, the tag contents will be mapped  into two separate notes of type "Access Restrictions" in the Toolkit.

      # @id	ALL @id attributes on note tags map to the persistent_id property

      # Simple Notes
    it "maps '<abstract>' correctly" do
      note_content(get_note_by_type(@resource, 'abstract')).should eq("Resource-Abstract-AT")
    end

    it "maps '<accessrestrict>' correctly" do
      nc = get_notes_by_type(@resource, 'accessrestrict').map {|note|
        note_content(note)
      }.flatten

      nc[0].should eq("<p>Resource-ConditionsGoverningAccess-AT</p>")
      nc[1].should eq("<legalstatus>Resource-LegalStatus-AT</legalstatus>")
    end

    it "maps '<accruals>' correctly" do
      note_content(get_note_by_type(@resource, 'accruals')).should eq("<p>Resource-Accruals-AT</p>")
    end

    it "maps '<acqinfo>' correctly" do
      note_content(get_note_by_type(@resource, 'acqinfo')).should eq("<p>Resource-ImmediateSourceAcquisition</p>")
    end

    it "maps '<altformavail>' correctly" do
      note_content(get_note_by_type(@resource, 'altformavail')).should eq("<p>Resource-ExistenceLocationCopies-AT</p>")
    end

    it "maps '<appraisal>' correctly" do
      note_content(get_note_by_type(@resource, 'appraisal')).should eq("<p>Resource-Appraisal-AT</p>")
    end

    it "maps '<arrangement>' correctly" do
      note_content(get_note_by_type(@resource, 'arrangement')).should eq("<p>Resource-Arrangement-Note</p>")
    end

    it "maps '<bioghist>' correctly" do
      @archival_objects['06']['notes'].find{|n| n['type'] == 'bioghist'}['persistent_id'].should eq('ref50')
      @archival_objects['12']['notes'].find{|n| n['type'] == 'bioghist'}['persistent_id'].should eq('ref53')
      @resource['notes'].select{|n| n['type'] == 'bioghist'}.map{|n| n['persistent_id']}.sort.should eq(['ref47', 'ref7'])
    end

    it "maps '<custodhist>' correctly" do
      note_content(get_note_by_type(@resource, 'custodhist')).should eq("<p>Resource--CustodialHistory-AT</p>")
    end

    it "maps '<dimensions>' correctly" do
      note_content(get_note_by_type(@resource, 'dimensions')).should eq("Resource-Dimensions-AT")
    end

    it "maps '<fileplan>' correctly" do
      note_content(get_note_by_type(@resource, 'fileplan')).should eq("<p>Resource-FilePlan-AT</p>")
    end

    it "maps '<langmaterial>' correctly" do
      @archival_objects['06']['language'].should eq('eng')
    end

    it "maps '<legalstatus>' correctly" do
      note_content(get_note_by_type(@resource, 'legalstatus')).should eq("Resource-LegalStatus-AT")
    end

    it "maps '<materialspec>' correctly" do
      get_note_by_type(@resource, 'materialspec')['persistent_id'].should eq("ref22")
    end

    it "maps '<note>' correctly" do
      # 	IF nested in <archdesc> OR <c>

      # 	ELSE, IF nested in <notestmnt>
      @resource['finding_aid_note'].should eq("<p>Resource-FindingAidNote-AT</p>")
      # 	ELSE
    end

    it "maps '<odd>' correctly" do
      @resource['notes'].select{|n| n['type'] == 'odd'}.map{|n| n['persistent_id']}.sort.should eq(%w(ref45 ref44 ref15).sort)
    end

    it "maps '<originalsloc>' correctly" do
      get_note_by_type(@resource, 'originalsloc')['persistent_id'].should eq("ref13")
    end

    it "maps '<otherfindaid>' correctly" do
      get_note_by_type(@resource, 'otherfindaid')['persistent_id'].should eq("ref23")
    end

    it "maps '<physfacet>' correctly" do
      note_content(get_note_by_type(@resource, 'physfacet')).should eq("Resource-PhysicalFacet-AT")
    end

    it "maps '<physloc>' correctly" do
      get_note_by_type(@resource, 'physloc')['persistent_id'].should eq("ref21")
    end

    it "maps '<phystech>' correctly" do
      get_note_by_type(@resource, 'phystech')['persistent_id'].should eq("ref24")
    end

    it "maps '<prefercite>' correctly" do
      get_note_by_type(@resource, 'prefercite')['persistent_id'].should eq("ref26")
    end

    it "maps '<processinfo>' correctly" do
      get_note_by_type(@resource, 'prefercite')['persistent_id'].should eq("ref26")
    end

    it "maps '<relatedmaterial>' correctly" do
      get_note_by_type(@resource, 'prefercite')['persistent_id'].should eq("ref26")
    end

    it "maps '<scopecontent>' correctly" do
      get_note_by_type(@resource, 'scopecontent')['persistent_id'].should eq("ref29")
      @archival_objects['01']['notes'].find{|n| n['type'] == 'scopecontent'}['persistent_id'].should eq("ref43")
    end

    it "maps '<separatedmaterial>' correctly" do
      get_note_by_type(@resource, 'separatedmaterial')['persistent_id'].should eq("ref30")
    end

    it "maps '<userestrict>' correctly" do
      get_note_by_type(@resource, 'userestrict')['persistent_id'].should eq("ref9")
    end

    # Structured Notes
    it "maps '<bibliography>' correctly" do
      #   	IF nested in <archdesc>  OR <c>
      @resource['notes'].find{|n| n['jsonmodel_type'] == 'note_bibliography'}['persistent_id'].should eq("ref6")
      @archival_objects['06']['notes'].find{|n| n['jsonmodel_type'] == 'note_bibliography'}['persistent_id'].should eq("ref48")
      @archival_objects['12']['notes'].find{|n| n['jsonmodel_type'] == 'note_bibliography'}['persistent_id'].should eq("ref51")
      #     <head>
      @archival_objects['06']['notes'].find{|n| n['persistent_id'] == 'ref48'}['label'].should eq("Resource--C06-Bibliography")
      #     <p>
      @archival_objects['06']['notes'].find{|n| n['persistent_id'] == 'ref48'}['content'][0].should eq("Resource--C06--Bibliography--Head")
      #     <bibref>
      @archival_objects['06']['notes'].find{|n| n['persistent_id'] == 'ref48'}['items'][0].should eq("c06 bibItem2")
      @archival_objects['06']['notes'].find{|n| n['persistent_id'] == 'ref48'}['items'][1].should eq("c06 bibItem1")
      #     other nested and inline elements
    end

    it "maps '<index>' correctly" do
      # 	IF nested in <archdesc>  OR <c>
      ref52 = get_note(@archival_objects['12'], 'ref52')
      ref52['jsonmodel_type'].should eq('note_index')
      #     <head>
      ref52['label'].should eq("Resource-c12-Index")
      #     <p>
      ref52['content'][0].should eq("Resource-c12-index-note")
      #     <indexentry>
      #         <name>

      #         <persname>

      #         <famname>
      ref52['items'].find{|i| i['type'] == 'family'}['value'].should eq('Bike 2')
      #         <corpname>
      ref52['items'].find{|i| i['type'] == 'corporate_entity'}['value'].should eq('Bike 3')
      #         <subject>

      #         <function>

      #         <occupation>

      #         <genreform>
      ref52['items'].find{|i| i['type'] == 'genre_form'}['value'].should eq('Bike 1')
      #         <title>

      #         <geogname>

      #         <ref>
      #     other nested and inline elements
    end


    # Mixed Content Note Parts
    it "maps '<chronlist>' correctly" do
      #     <head>
      #     <chronitem>
      #         <date>
      #         <event>
      ref53 = get_note(@archival_objects['12'], 'ref53')
      get_subnotes_by_type(ref53, 'note_chronology')[0]['items'][0]['events'][0].should eq('first date')
      get_subnotes_by_type(ref53, 'note_chronology')[0]['items'][1]['events'][0].should eq('second date')

      #         <eventgrp><event>
      ref50 = get_subnotes_by_type(get_note(@archival_objects['06'], 'ref50'), 'note_chronology')[0]
      item = ref50['items'].find{|i| i['event_date'] && i['event_date'] == '1895'}
      item['events'].sort.should eq(['Event1', 'Event2'])
      #         other nested and inline elements
    end

    # WHEN @type = deflist OR @type = NULL AND <defitem> present
    it "maps '<list>' correctly" do
      ref47 = get_note(@resource, 'ref47')
      note_dl = ref47['subnotes'].find{|n| n['jsonmodel_type'] == 'note_definedlist'}
      #     <head>
      note_dl['title'].should eq("Resource-BiogHist-structured-top-part3-listDefined")
      #     <defitem>	WHEN <list> @type = deflist
      #         <label>
      note_dl['items'].map {|i| i['label']}.sort.should eq(['MASI SLP', 'Yeti Big Top', 'Intense Spider 29'].sort)
      #         <item>
      note_dl['items'].map {|i| i['value']}.sort.should eq(['2K', '2500 K', '4500 K'].sort)
      # ELSE WHEN @type != deflist AND <defitem> not present
      ref44 = get_note(@resource, 'ref44')
      note_ol = get_subnotes_by_type(ref44, 'note_orderedlist')[0]
      #     <head>
      note_ol['title'].should eq('Resource-GeneralNoteMULTIPARTLISTTitle-AT')
      #     <item>
      note_ol['items'].sort.should eq(['Resource-GeneralNoteMULTIPARTLISTItem1-AT', 'Resource-GeneralNoteMULTIPARTLISTItem2-AT'])
    end

    # CONTAINER INFORMATION
    # Up to three container elements can be imported per <c>.
    # The Asterisks in the target element field below represents the numbers "1", "2", or "3" depending on which <container> tag the data is coming from

    it "maps '<container>' correctly" do
      i = @archival_objects['02']['instances'][0]
      i['instance_type'].should eq('mixed_materials')
      i['container']['indicator_1'].should eq('2')
      i['container']['indicator_2'].should eq('2')
      #   @type
      i['container']['type_1'].should eq('Box')
      i['container']['type_2'].should eq('Folder')
    end

    # DAO's
    it "maps '<dao>' correctly" do
      @digital_objects.length.should eq(12)
      links = @archival_objects['01']['instances'].select{|i| i.has_key?('digital_object')}.map{|i| i['digital_object']['ref']}
      links.sort.should eq(@digital_objects.map{|d| d['uri']}.sort)
      #   @titles
      @digital_objects.map {|d| d['title']}.include?("DO.Child2Title-AT").should be(true)
      #   @role
      uses = @digital_objects.map {|d| d['file_versions'].map {|f| f['use_statement']}}.flatten
      uses.uniq.sort.should eq(["Image-Service", "Image-Master", "Image-Thumbnail"].sort)
      #   @href
      uris = @digital_objects.map {|d| d['file_versions'].map {|f| f['file_uri']}}.flatten
      (uris.include?('DO.Child1URI2-AT')).should be(true)
      #   @actuate
      @digital_objects.select{|d| d['file_versions'][0]['xlink_actuate_attribute'] == 'onRequest'}.length.should eq(9)
      #   @show
      @digital_objects.select{|d| d['file_versions'][0]['xlink_show_attribute'] == 'new'}.length.should eq(3)
    end

    # FORMAT & STRUCTURE
    it "maps '<archdesc>' correctly" do
      #   @level	IF != NULL
      @resource['level'].should eq("collection")
      # 	ELSE
      #   @otherlevel
    end

    it "maps '<c>' correctly" do
      #   @level	IF != NULL
      @archival_objects['04']['level'].should eq('file')
      # 	ELSE
      #   @otherlevel
      #   @id
      @archival_objects['05']['ref_id'].should eq('ref34')
    end
  end

  describe "Mapping the EAD @audience attribute" do
    let (:test_doc) {
          src = <<ANEAD
<ead>
  <archdesc level="collection" audience="internal">
  <did>
       <descgrp>                                                      
          <processinfo/>                                                 
      </descgrp>  
      <unittitle>Resource--Title-AT</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <physdesc>
        <extent>5.0 Linear feet</extent>
        <extent>Resource-ContainerSummary-AT</extent>
      </physdesc>
    </did>
    <dsc>
    <c id="1" level="file" audience="internal">
      <unittitle>oh well</unittitle>
      <unitdate normal="1907/1911" era="ce" calendar="gregorian" type="inclusive">1907-1911</unitdate>
    </c>
    <c id="2" level="file" audience="external">
      <unittitle>whatever</unittitle>
      <container id="cid3" type="Box" label="Text">FOO</container>
    </c>
    </dsc>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    before do
      parsed = convert(test_doc)
      @resource = parsed.find{|r| r['jsonmodel_type'] == 'resource'}
      @components = parsed.select{|r| r['jsonmodel_type'] == 'archival_object'}
    end      

    it "uses archdesc/@audience to set resource publish property" do
      @resource['publish'].should be false
    end

    it "uses c/@audience to set component publish property" do
      @components[0]['publish'].should be false
      @components[1]['publish'].should be true
    end
  end

  describe "Non redundant mapping" do
    let (:test_doc) {
          src = <<ANEAD
<ead>
  <archdesc level="collection">
    <did>
      <unittitle>Resource--Title-AT</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <physdesc>
        <extent>5.0 Linear feet</extent>
        <extent>Resource-ContainerSummary-AT</extent>
      </physdesc>
      <langmaterial>
        <language langcode="eng"/>
      </langmaterial>
    </did>
    <accruals id="ref2">
       <head>foo</head>
       <p>bar</p>
    </accruals>
    <odd id="ref44">
      <head>Resource-GeneralNoteMULTIPARTLISTLabel-AT</head>
      <list numeration="loweralpha" type="ordered">
        <head>Resource-GeneralNoteMULTIPARTLISTTitle-AT</head>
        <item>Resource-GeneralNoteMULTIPARTLISTItem1-AT</item>
        <item>Resource-GeneralNoteMULTIPARTLISTItem2-AT</item>
      </list>
    </odd>
    <dsc>
    <c id="1" level="file" audience="internal">
      <did>
        <unittitle>oh well</unittitle>
        <unitdate normal="1907/1911" era="ce" calendar="gregorian" type="inclusive">1907-1911</unitdate>
        <langmaterial>
          <language langcode="eng"/>
        </langmaterial>
      </did>
    </c>
    </dsc>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    before do
      parsed = convert(test_doc)
      @resource = parsed.find{|r| r['jsonmodel_type'] == 'resource'}
      @component = parsed.find{|r| r['jsonmodel_type'] == 'archival_object'}
    end

    it "only maps <language> content to one place" do
      @resource['language'].should eq 'eng'
      get_note_by_type(@resource, 'langmaterial').should be_nil

      @component['language'].should eq 'eng'
      get_note_by_type(@component, 'langmaterial').should be_nil
    end

    it "maps <head> tag to note label, but not to note content" do
      n = get_note_by_type(@resource, 'accruals')
      n['label'].should eq('foo')
      note_content(n).should_not match(/foo/)
    end

    # See: https://www.pivotaltracker.com/story/show/54942792
    # it "maps lists to a list subnote, and not a text subnote" do
    #   n = get_note_by_type(@resource, 'odd')
    #   get_subnotes_by_type(n, 'note_orderedlist').count.should eq(1)
    #   get_subnotes_by_type(n, 'note_text').should be_empty
    # end
  end

  # https://www.pivotaltracker.com/story/show/65722286
  describe "Mapping the unittitle tag" do
    let (:test_doc) {
          src = <<ANEAD
<ead>
  <archdesc level="collection" audience="internal">
    <did>
      <unittitle>一般行政文件 [2]</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <physdesc>
        <extent>5.0 Linear feet</extent>
        <extent>Resource-ContainerSummary-AT</extent>
      </physdesc>
    </did>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    it "maps the unittitle tag correctly" do
      json = convert(test_doc)
      resource = json.find{|r| r['jsonmodel_type'] == 'resource'}
      resource['title'].should eq("一般行政文件 [2]")
    end

  end


  describe "Mapping the langmaterial tag" do
    let (:test_doc) {
          src = <<ANEAD
<ead>
  <archdesc level="collection" audience="internal">
    <did>
      <unittitle>Title</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <langmaterial>
        <language langcode="eng">English</language>
      </langmaterial>
      <physdesc>
        <extent>5.0 Linear feet</extent>
        <extent>Resource-ContainerSummary-AT</extent>
      </physdesc>
    </did>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    it "should map the langcode to language, and the language text to a note" do
      json = convert(test_doc)
      resource = json.select {|rec| rec['jsonmodel_type'] == 'resource'}.last
      resource['language'].should eq('eng')

      langmaterial = get_note_by_type(resource, 'langmaterial')
      note_content(langmaterial).should eq('English')
    end
  end


  describe "extent and physdesc mapping logic" do
    let(:doc1) {
      src = <<ANEAD
<ead>
  <archdesc level="collection" audience="internal">
    <did>
      <unittitle>Title</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <langmaterial>
        <language langcode="eng">English</language>
      </langmaterial>
      <physdesc altrender="whole">
        <extent altrender="materialtype spaceoccupied">1 Linear Feet</extent>
      </physdesc>
      <physdesc altrender="whole">
        <extent altrender="materialtype spaceoccupied">1 record carton</extent>
      </physdesc>
    </did>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    let (:doc2) {
          src = <<ANEAD
<ead>
  <archdesc level="collection" audience="internal">
    <did>
      <unittitle>Title</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <langmaterial>
        <language langcode="eng">English</language>
      </langmaterial>
      <physdesc altrender="whole">
        <extent altrender="materialtype spaceoccupied">1 Linear Feet</extent>
        <extent altrender="materialtype spaceoccupied">1 record carton</extent>
      </physdesc>
    </did>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    let (:doc3) {
          src = <<ANEAD
<ead>
  <archdesc level="collection" audience="internal">
    <did>
      <unittitle>Title</unittitle>
      <unitid>Resource.ID.AT</unitid>
      <langmaterial>
        <language langcode="eng">English</language>
      </langmaterial>
      <physdesc altrender="whole">
        <extent altrender="materialtype spaceoccupied">1 Linear Feet</extent>
      </physdesc>
      <physdesc altrender="whole">
        <function>whatever</function>
      </physdesc>
    </did>
  </archdesc>
</ead>
ANEAD

      get_tempfile_path(src)
    }

    before(:all) do
      @resource1 = convert(doc1).select {|rec| rec['jsonmodel_type'] == 'resource'}.last
      @resource2 = convert(doc2).select {|rec| rec['jsonmodel_type'] == 'resource'}.last
      @resource3 = convert(doc3).select {|rec| rec['jsonmodel_type'] == 'resource'}.last
    end

    it "creates a single extent record for each physdec/extent[1] node" do
      @resource1['extents'].count.should eq(2)
      @resource2['extents'].count.should eq(1)
    end

    it "puts additional extent records in extent.container_summary" do
      @resource2['extents'][0]['container_summary'].should eq('1 record carton')
    end

    it "maps a physdec node to a note unless it only contains extent tags" do
      get_notes_by_type(@resource1, 'physdesc').length.should eq(0)
      get_notes_by_type(@resource2, 'physdesc').length.should eq(0)
      get_notes_by_type(@resource3, 'physdesc').length.should eq(1)
    end

  end
end
