# frozen_string_literal: true

module Forms
  def self.from_filings(filing_array)
    combine_forms(filing_array.map do |filing|
      case filing.form.to_i
      when 23
        Forms::Form410.new(filing, name: '410')
      when 30
        Forms::Form460.new(filing, name: '460')
      when 36
        Forms::Form496.new(filing, name: '496')
      when 39
        Forms::Form497.new(filing, name: '497')
      when 54 # Behested Payment Report
        Forms::BaseForm.new(filing, name: '803')
      when 115
        Forms::BaseForm.new(filing, name: 'SFEC 161')
      when 7, 199, 215, 220, 228, 254
        Forms::Form700.new(filing, name: '700')
      when 236 # LBQ = Oakland Lobbyist Quartery Report
        Forms::BaseForm.new(filing, name: 'LBQ')
      when 235 # LBR = Oakland Lobbyist Registration
        Forms::BaseForm.new(filing, name: 'LBR')
      else
        guessed_form_name = filing.title.match(/FPPC Form (\d+)/) ? $~[1] : nil

        if filing.form.to_i == 0 && guessed_form_name == '700'
          Forms::Form700.new(filing, name: guessed_form_name)
        else
          Forms::BaseForm.new(filing, name: guessed_form_name)
        end
      end
    end)
  end

  def self.combine_forms(forms)
    [].tap do |combined|
      # remove any forms that were later amended on the same day
      forms.delete_if do |form|
        forms.any? do |other_form|
          next if other_form.id == form.id

          other_form.amended_filing_id.to_i == form.id ||
            (other_form.amended_filing_id.to_i == form.amended_filing_id.to_i &&
             other_form.amendment_sequence_number.to_i > form.amendment_sequence_number.to_i)
        end
      end

      # combine 496's from the same filer on the same day
      while forms.any?
        current_form = forms.shift
        can_combine_forms = forms.find_all { |f| current_form.can_combine_with?(f) }
        combined << if can_combine_forms.any?
                      Forms::Form496Combined.new(
                        [current_form.filing] + can_combine_forms.map(&:filing),
                        name: '496 Combined',
                      )
                    else
                      current_form
                    end
        can_combine_forms.each do |combined_form|
          forms.delete(combined_form)
        end
      end
    end
  end

  class BaseForm
    delegate :id, :filer_id, :title, :filed_at, :amendment_sequence_number,
      :amended_filing_id, :form, :contents, :contents_xml, to: :@filing
    attr_reader :form_name, :filing

    def initialize(filing, name: nil)
      @filing = filing
      @form_name = name
    end

    # Override in a subclass if a better name can be presented to the user.
    def filer_name
      @filing.filer_name
    end

    # Override in a subclass
    # @retun {Hash?} Returns a hash with keys position, agency, and
    # division_board_district.
    def filer_title; end

    # I18n key to describe the Form
    def i18n_key
      return 'forms.unknown' unless @filing.form_name.present?
      key = "forms.#{@filing.form_name.delete(' ')}"
      return 'forms.unknown' unless I18n.exists?(key)

      key
    end

    def amendment?
      @filing.amended_filing_id?
    end

    def amended_filing
      return unless amendment?

      self.class.new(@filing.amended_filing, name: @filing.form_name)
    end

    def spreadsheet_candidate
      @filing.election_candidates.last
    end

    def spreadsheet_committee
      @filing.election_committee
    end

    def spreadsheet_referendum
      @filing.election_referendum
    end

    def uncombined_filing_ids
      []
    end

    def can_combine_with?(_other_form)
      false
    end
  end

  class BaseXMLForm < BaseForm
    def initialize(filing, name: nil)
      super

      @xml = Nokogiri::XML(contents_xml, &:noblanks) if contents_xml.present?
    end
  end
end
