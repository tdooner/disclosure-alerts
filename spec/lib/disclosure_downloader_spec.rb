require 'rails_helper'

RSpec.describe DisclosureDownloader do
  class FakeNetfileClient
    def initialize(fake_filings)
      @filings = Array(fake_filings)
    end

    def each_filing(agency:, &block)
      @filings.each { |filing| block.call(filing.metadata) }
    end

    def fetch_transaction_contents(id)
      @filings
        .find { |filing| filing.metadata['id'].to_i == id.to_i }
        .data
    end
  end

  FakeFiling = Struct.new(:metadata, :data)

  describe '#download' do
    let(:fake_client) { FakeNetfileClient.new([fake_filing]) }
    let(:fake_filing) { FakeFiling.new(fake_filing_metadata, fake_filing_data) }
    let(:fake_filing_metadata) do
      {
        id: "12345",
        filerStateId: "1111",
        filerName: 'Foo bar for Mayor',
        title: "title",
        filingDate: "#{Date.today - 1}T17:50:07.0000000-07:00",
        amendmentSequenceNumber: 0,
        amendedFilingId: nil,
        form: 36, # FPPC Form 496
        agency: NetfileAgency.coak.netfile_id,
      }.stringify_keys
    end
    let(:fake_filing_data) do
      [
        {
          "form_Type"=>"F496",
          "tran_Dscr"=>"Online ads",
          "tran_Date"=>"2022-10-11T00:00:00.0000000-07:00",
          "calculated_Amount"=>10000.0,
          "cand_NamL"=>"Foo Bar",
          "sup_Opp_Cd"=>"S",
          "bal_Name"=>"",
          "bal_Num"=>"",
          "tran_NamL"=>nil,
          "tran_NamF"=>nil,
          "tran_City"=>nil,
          "tran_Zip4"=>nil,
          "tran_Emp"=>nil,
          "tran_Occ"=>nil,
          "tran_Amt1"=>10000.0,
          "tran_Amt2"=>nil,
          "entity_Cd"=>nil,
          "cmte_Id"=>nil
        }
      ]
    end

    before do
      allow(Netfile::Client).to receive(:new).and_return(fake_client)
    end

    it 'downloads a 496 filing' do
      expect { described_class.new.download }
        .to change(Filing, :count)
        .by(1)

      last_filing = Filing.last
      expect(last_filing.title).to eq(fake_filing.metadata['title'])
      expect(last_filing.netfile_agency).to eq(NetfileAgency.coak)
    end
  end
end
