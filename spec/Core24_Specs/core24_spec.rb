require 'spec_helper'



describe "Core 24 test" do

def test(file)
jsonfile = File.open(file).read
json_response = Application.new(jsonfile, 'application/json')
@json_response = JSON.parse(json_response.to_json) 
puts "The number of applicants in this json file: #{@json_response['Applicants'].count}"
return @json_response
end

shared_examples_for "Core 24 tests" do

		it "Compares FPL" do
		@json_response["Applicants"].each_with_index do |applicant, index|
		expect(applicant['Medicaid Household']['MAGI as Percentage of FPL']).to eq @person[index][:FPL]
		end
		end

		it "Compares Medicaid Eligibilty " do
		@json_response["Applicants"].each_with_index do |applicant, index|
		expect(applicant['Medicaid Eligible']).to eq @person[index][:MedicaidEligible]
		end
		end

		it "Compares MAGI" do
		@json_response["Applicants"].each_with_index do |applicant, index|
		expect(applicant['Medicaid Household']['MAGI']).to eq @person[index][:MAGI]
		end
		end

		it "Compares APTC Referal" do
		@json_response["Applicants"].each_with_index do |applicant, index|
		expect(applicant['Determinations']['APTC Referral']['Indicator']).to eq @person[index][:APTCReferal]
		end
		end

end

describe "QA-CORE-1-UA-012.json" do

before(:all) do
@json_response = test('spec/core24/QA-CORE-1-UA-012.json')
@person = []
@person << { FPL: 84, MAGI: 10000, MedicaidEligible: 'N', APTCReferal: 'Y'}
end

it_behaves_like "Core 24 tests"

end


describe "test_QACORE8MAGIIAUA004_married_filing_separately_big_household" do

	before(:all) do
	@json_response = test('spec/core24/QA-CORE-8-MAGI_IA_UA-004.json')
	@person = []
		
		@person << {FPL: 240, MAGI: 88348, MedicaidEligible: 'N', APTCReferal: 'Y'}
		@person << {FPL: 407, MAGI: 81939, MedicaidEligible: 'N', APTCReferal: 'Y'}
		@person << {FPL: 407, MAGI: 81939, MedicaidEligible: 'N', APTCReferal: 'Y'}
		@person << {FPL: 240, MAGI: 88348, MedicaidEligible: 'N', APTCReferal: 'Y'}
		@person << {FPL: 0, MAGI: 0, MedicaidEligible: 'Y', APTCReferal: 'N'}
		@person << {FPL: 0, MAGI: 0, MedicaidEligible: 'Y', APTCReferal: 'N'}
		@person << {FPL: 0, MAGI: 0, MedicaidEligible: 'N', APTCReferal: 'Y'}
		@person << {FPL: 0, MAGI: 0, MedicaidEligible: 'Y', APTCReferal: 'N'}

	end

it_behaves_like "Core 24 tests"
end


end
	