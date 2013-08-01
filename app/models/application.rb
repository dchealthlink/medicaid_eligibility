 class Application
  def initialize(raw_application, return_application)
    @raw_application = raw_application
    @xml_application = Nokogiri::XML(raw_application) do |config|
     config.default_xml.noblanks
    end
    @return_application = return_application
  end

  def validate
  end

  def result
    context = build_context
    output = process_rules(context)
    update_xml!(output)
  end

  private

  def return_application?
    @return_application
  end

  def update_xml!(output)
    unless return_application?
      node = get_value("exch:AccountTransferRequest").first
      node.children.remove
      Nokogiri::XML::Builder.with(node) do |xml|
        xml.send("hix-ee:InsuranceApplication") {
          output["Applicants"].each do |applicant|
            xml.send("hix-ee:InsuranceApplicant",:id => applicant["id"])
          end
        }
      end
    end

    for applicant in output["Applicants"]
      xml_applicant = get_value("/exch:AccountTransferRequest/hix-ee:InsuranceApplication/hix-ee:InsuranceApplicant").find{
        |app| app.attribute("id").value == applicant["id"]
      }

      for output_var, output_value in applicant.except("id")
        xpath = output_variables[output_var][:xpath]
        find_or_create_node(xml_applicant, xpath).content = output_value
      end
    end
    @xml_application
  end

  def get_value(xpath)
    @xml_application.xpath(xpath, {
          "exch"     => "http://at.dsh.cms.gov/exchange/1.0",
          "s"        => "http://niem.gov/niem/structures/2.0", 
          "ext"      => "http://at.dsh.cms.gov/extension/1.0",
          "hix-core" => "http://hix.cms.gov/0.1/hix-core", 
          "hix-ee"   => "http://hix.cms.gov/0.1/hix-ee",
          "nc"       => "http://niem.gov/niem/niem-core/2.0", 
          "hix-pm"   => "http://hix.cms.gov/0.1/hix-pm",
          "scr"      => "http://niem.gov/niem/domains/screening/2.1"
     } )
  end

  def set_value(xpath, value)
  end

  def build_context
    state = get_value("/exch:AccountTransferRequest/ext:TransferHeader/ext:TransferActivity/ext:RecipientTransferActivityStateCode").inner_text
    
    config = MedicaidEligibilityApi::Application.options[:config][state] || MedicaidEligibilityApi::Application.options[:config][:default]
    input = {
      "State"      => state,
      "Applicants" => []
    }

    applicants = get_value "/exch:AccountTransferRequest/hix-ee:InsuranceApplication/hix-ee:InsuranceApplicant"
    
    for app in applicants
      app_data = {}
      app_id = app.attribute('id').value
      app_data['id'] = app_id

      person = get_value("/exch:AccountTransferRequest/hix-core:Person").find{
        |p| p.attribute('id').value == app.at_xpath("hix-core:RoleOfPersonReference").attribute('ref').value
      }
      
      for app_var, app_var_info in applicant_variables
        if app_var_info[:group] == :applicants
          node = app.at_xpath(app_var_info[:xpath])
        elsif app_var_info[:group] == :people
          node = person.at_xpath(app_var_info[:xpath])
        else
          raise "No group listed for variable #{app_var}"
        end

        if node
          if app_var_info[:values]
            app_data[app_var] = app_var_info[:values][node.inner_text]
          elsif app_var_info[:type] == :integer
            app_data[app_var] = node.inner_text.to_i
          else
            app_data[app_var] = node.inner_text
          end
        elsif app_var_info[:required]
          raise "Input xml missing required variable #{app_var} for applicant #{app_id}"
        elsif app_var_info[:missing_val]
          app_data[app_var] = app_var_info[:missing_val]
        else
          raise "Missing default value for variable #{app_var}"
        end
      end

      # We need additional information passed to us, since we
      # don't have birthdates; this is just a quick fix for now
      app_data["Applicant Post Partum Period Indicator"] = 'N'

      input["Applicants"] << app_data
    end

    RuleContext.new(config, input)
  end

  def applicant_variables
    @applicant_variables ||= {
      "Medicaid Residency Status Indicator" => {
        :group => :applicants,
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIResidencyEligibilityBasis/hix-ee:StatusIndicator",
        :required => false,
        :values => {
          'Y' => 'Y',
          'true' => 'Y',
          'N' => 'N',
          'false' => 'N'
        },
        :missing_val => 'N'
      },
      "Applicant Medicaid Citizen Or Immigrant Status Indicator" => {
        :group => :applicants,
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGICitizenOrImmigrantEligibilityBasis/hix-ee:StatusIndicator",
        :required => false,
        :values => {
          'Y' => 'Y',
          'true' => 'Y',
          'N' => 'N',
          'false' => 'N'
        },
        :missing_val => 'N'
      },
      "Applicant Pregnant Indicator" => {
        :group => :people,
        :xpath => "hix-core:PersonAugmentation/hix-core:PersonPregnancyStatus/hix-core:StatusIndicator",
        :required => false,
        :values => {
          'Y' => 'Y',
          'true' => 'Y',
          'N' => 'N',
          'false' => 'N'
        },
        :missing_val => 'N'
      },
      "Applicant Age" => {
        :group => :people,
        :xpath => "PersonAge",
        :required => true,
        :type => :integer
      }
    }
  end

  def output_variables
    @output_variables ||= {
      "Applicant Pregnancy Category Indicator" => {
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIPregnancyCategoryEligibilityBasis/hix-core:StatusIndicator"
      },
      "Pregnancy Category Determination Date" => {
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIPregnancyCategoryEligibilityBasis/hix-ee:EligibilityBasisDetermination/nc:ActivityDate/nc:DateTime"
      },
      "Pregnancy Category Ineligibility Reason" => {
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIPregnancyCategoryEligibilityBasis/hix-ee:EligibilityBasisIneligibilityReasonText"
      },
      "Applicant Child Category Indicator" => {
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIChildCategoryEligibilityBasis/hix-core:StatusIndicator"
      },
      "Child Category Determination Date" => {
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIChildCategoryEligibilityBasis/hix-ee:EligibilityBasisDetermination/nc:ActivityDate/nc:DateTime"
      },
      "Child Category Ineligibility Reason" => {
        :xpath => "hix-ee:MedicaidMAGIEligibility/hix-ee:MedicaidMAGIChildCategoryEligibilityBasis/hix-ee:EligibilityBasisIneligibilityReasonText"
      }
    }
  end

  def process_rules(initial_context)
    final_output = {
      "Applicants" => []
    }

    for applicant in initial_context.input["Applicants"]
      applicant_context = RuleContext.new(initial_context.config, applicant)
      applicant_output = {
        "id" => applicant["id"]
      }
      for ruleset in ruleset_order
        ruleset.new().run(applicant_context)
        applicant_output.merge!(applicant_context.output)

        applicant_context = RuleContext.new(applicant_context.config, applicant_context.input.merge(applicant_context.output))
      end
      final_output["Applicants"] << applicant_output
    end

    final_output
  end

  def ruleset_order
    @ruleset_order ||= [
      Medicaidchip::Eligibility::Category::Pregnant,
      Medicaidchip::Eligibility::Category::Child
    ]
  end

  def find_or_create_node(node, xpath)
    xpath.gsub!(/^\/+/,'')
    if xpath.empty?
      node
    elsif node.at_xpath(xpath)
      node.at_xpath(xpath)
    else
      xpath_list = xpath.split('/')
      next_node = node.at_xpath(xpath_list.first)
      if next_node
        find_or_create_node(next_node, xpath_list[1..-1].join('/'))
      else
        Nokogiri::XML::Builder.with(node) do |xml|
          xml.send(xpath_list.first)
        end

        find_or_create_node(node.at_xpath(xpath_list.first), xpath_list[1..-1].join('/'))
      end
    end
  end
end
