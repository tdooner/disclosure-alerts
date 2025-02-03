# frozen_string_literal: true

class DisclosureDownloader
  def initialize(agency = NetfileAgency.coak)
    @netfile = Netfile::Client.new
    @agency = agency
  end

  def download
    latest = Filing.where(netfile_agency: @agency).order(filed_at: :desc).first
    puts '==================================================================='
    puts "Beginning State for Netfile agency #{@agency.shortcut}:"
    puts
    puts "Filings: #{Filing.where(netfile_agency: @agency).count}"
    puts "Latest: #{latest&.filed_at}"
    puts '==================================================================='

    @netfile.each_filing(agency: @agency) do |json|
      filing = Filing.from_json(json)

      if filing.new_record?
        puts "Syncing new filing: #{filing.inspect}"
      end

      break if Date.today - filing.filed_at.to_date > 14

      download_filing(filing) if filing.new_record?
      filing.save

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

    latest = Filing.where(netfile_agency: @agency).order(filed_at: :desc).first
    puts '==================================================================='
    puts 'Ending State:'
    puts
    puts "Filings: #{Filing.where(netfile_agency: @agency).count}"
    puts "Latest: #{latest&.filed_at}"
    puts '==================================================================='
  end

  # Goes through old Filings and downloads the contents if missing.
  def backfill_contents
    puts '==================================================================='
    puts 'Backfilling Filings:'
    puts
    puts "Filings: #{Filing.count}"
    puts '==================================================================='

    num_backfilled_by_name = Hash.new(0)
    Filing.find_each do |filing|
      next unless ['410'].include?(filing.form_name)
      next if filing.contents.present?

      download_filing(filing)
      num_backfilled_by_name[filing.form_name] += 1
    end

    puts '==================================================================='
    puts 'Backfill Completed:'
    puts
    puts "Backfilled: #{num_backfilled_by_name.map { |k, v| "Form #{k}: #{v}" }.join(', ')}"
    puts '==================================================================='
  end

  private

  def download_filing(filing)
    contents =
      case filing.form_name
      when '410'
        raw = @netfile.fetch_calfile(filing.id)
        raw.present? ? raw.lines : nil
      # TODO: Reenable when we've completed CAL file parsing
      # when '460'
      #   @netfile
      #     .fetch_summary_contents(filing.id)
      #     .map { |row| row.slice('form_Type', 'line_Item', 'amount_A') }
      # when '497'
      #   @netfile
      #     .fetch_transaction_contents(filing.id)
      #     .map { |row| row.slice('form_Type', 'tran_NamL', 'calculated_Amount') }
      # when '496'
      #   @netfile
      #     .fetch_transaction_contents(filing.id)
      #     .map do |row|
      #       row.slice(*%w[
      #         form_Type tran_Dscr tran_Date calculated_Amount cand_NamL
      #         sup_Opp_Cd bal_Name bal_Num tran_NamL tran_NamF tran_City tran_Zip4 tran_Emp tran_Occ
      #         tran_Amt1 tran_Amt2 entity_Cd cmte_Id
      #       ])
      #   end
      end

    contents_xml =
      case filing.form_name
      when '700'
        @netfile
          .fetch_calfile(filing.id)
      end

    filing.update(contents: contents, contents_xml: contents_xml)
  rescue StandardError => ex
    raise FilingDownloadError, "Error downloading filing #{filing.id}: #{ex.message}"
  end

  class FilingDownloadError < StandardError; end
end
