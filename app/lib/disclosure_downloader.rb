# frozen_string_literal: true

class DisclosureDownloader
  def initialize
    @netfile = Netfile::Client.new
  end

  def download
    latest = Filing.order(filed_at: :desc).first
    puts '==================================================================='
    puts 'Beginning State:'
    puts
    puts "Filings: #{Filing.count}"
    puts "Latest: #{latest&.filed_at}"
    puts '==================================================================='

    @netfile.each_filing do |json|
      filing = Filing.from_json(json)

      if filing.new_record?
        puts "Syncing new filing: #{filing.inspect}"
      end

      break if latest && latest == filing
      break if Date.today - filing.filed_at.to_date > 14

      download_filing(filing)

      # If the filing was amended, but we haven't downloaded the original
      # un-amended filing yet, let's grab it now.
      if filing.amended_filing_id && !Filing.exists?(filing.amended_filing_id)
        amended_json = @netfile.get_filing(filing.amended_filing_id)
        # Netfile bug: Some fields have different names in the GET
        # /public/filing/info/{FilingId} endpoint than in the filing list
        # endpoint.
        amended_json['id'] = amended_json['filingId']
        amended_json['filerStateId'] = amended_json['sosFilerId']
        amended_json['amendedFilingId'] = amended_json['amends']
        # And some fields are missing.
        amended_json['agency'] = json['agency']
        amended_json['title'] = json['title']
        amended_json['form'] = json['form']
        amended_filing = Filing.from_json(amended_json)
        puts "Syncing un-amended filing: #{amended_filing}"
        download_filing(amended_filing)
      end
    end

    latest = Filing.order(filed_at: :desc).first
    puts '==================================================================='
    puts 'Ending State:'
    puts
    puts "Filings: #{Filing.count}"
    puts "Latest: #{latest&.filed_at}"
    puts '==================================================================='
  end

  private

  def download_filing(filing)
    contents =
      case filing.form_name
      when '460'
        @netfile
          .fetch_summary_contents(filing.id)
          .map { |row| row.slice('form_Type', 'line_Item', 'amount_A') }
      when '497 LCR', '497 LCM'
        @netfile
          .fetch_transaction_contents(filing.id)
          .map { |row| row.slice('form_Type', 'tran_NamL', 'calculated_Amount') }
      when '496'
        @netfile
          .fetch_transaction_contents(filing.id)
          .map { |row| row.slice('tran_Dscr', 'tran_Date', 'calculated_Amount', 'cand_NamL', 'sup_Opp_Cd', 'bal_Name', 'bal_Num') }
      end

    contents_xml =
      case filing.form_name
      when '700'
        @netfile
          .fetch_calfile_xml(filing.id)
      end

    filing.update_attributes(contents: contents, contents_xml: contents_xml)
  end
end
