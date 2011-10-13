require_relative '../language'
require_relative '../spatial'
require_relative '../kmeans'

module PdfExtract
  module Sections

    @@letter_ratio_threshold = 0.3

    @@width_ratio = 0.9

    @@body_content_threshold = 0.25
    
    def self.match? a, b
      lh = a[:line_height].round(2) == b[:line_height].round(2)
      
      f = a[:font] == b[:font]

      # lra = Language.letter_ratio(Spatial.get_text_content a)
      # lrb = Language.letter_ratio(Spatial.get_text_content b)
      # lr = (lra - lrb).abs <= @@letter_ratio_threshold
      
      # XXX Disabled since it doesn't seem to match.
      lr = true
      
      lh && f && lr
    end

    def self.candidate? region, column
      # Regions that make up sections or headers must be
      # both less width than their column width and,
      # unless they are a single line, must be within the
      # @@width_ratio.
      within_column = region[:width] <= column[:width]
      if Spatial.line_count(region) <= 1
        within_column
      else
        within_column && (region[:width].to_f / column[:width]) >= @@width_ratio
      end
    end

    def self.reference_cluster clusters
      # Find the cluster with name_ratio closest to 0.1
      # Those are our reference sections.
      ideal = 0.1
      ref_cluster = nil
      smallest_diff = 1
      
      clusters.each do |cluster|
        diff = (cluster[:centre][:name_ratio] - ideal).abs
        if diff < smallest_diff
          ref_cluster = cluster
          smallest_diff = diff
        end
      end

      ref_cluster
    end

    def self.clusters_to_spatials clusters
      clusters.map do |cluster|
        cluster[:items].each do |item|
          centre = cluster[:centre].values.map { |v| v.round(3) }.join ", "
          item[:centre] = centre
        end
        cluster[:items]
      end.flatten
    end

    def self.add_content_stats sections
      sections.map do |section|
        content = Spatial.get_text_content section
        Spatial.drop_spatial(section).merge({
          :letter_ratio => Language.letter_ratio(content),
          :year_ratio => Language.year_ratio(content),                              
          :name_ratio => Language.name_ratio(content),
          :word_count => Language.word_count(content)
        })
      end
    end
      
    def self.include_in pdf
      pdf.spatials :sections, :depends_on => [:regions, :columns] do |parser|

        columns = []
        
        parser.objects :columns do |column|
          columns << {:column => column, :regions => []}
        end

        parser.objects :regions do |region|
          containers = columns.reject do |c|
            column = c[:column]
            not (column[:page] == region[:page] && Spatial.contains?(column, region))
          end

          containers.first[:regions] << region unless containers.count.zero?
        end

        parser.after do
          # Sort regions in each column from highest to lowest.
          columns.each do |c|
            c[:regions].sort_by! { |r| -r[:y] }
          end

          # Group columns into pages.
          pages = {}
          columns.each do |c|
            pages[c[:column][:page]] ||= []
            pages[c[:column][:page]] << c
          end

          # Sort bodies on each page from x left to right.
          pages.each_pair do |page, columns|
            columns.sort_by! { |c| c[:column][:x] }
          end

          sections = []
          
          pages.each_pair do |page, columns|
            columns.each do |c|
              column = c[:column]
              c[:regions].each do |region|

                if candidate? region, column
                  if !sections.last.nil? && match?(sections.last, region)
                    content = Spatial.merge_lines(sections.last, region, {})
                    sections.last.merge!(content)
                  else
                    sections << region
                  end
                end
                
              end
            end
          end

          # We now have sections. Add information to them.
          # add_content_types sections
          sections = add_content_stats sections

          # Score sections into categories based on their textual attributes.
          ideals = {
            :reference => {
              :name_ratio => 0.1,
              :letter_ratio => 0.2,
              :year_ratio => 0.05
            },
            :body => {
              :name_ratio => 0.03,
              :letter_ratio => 0.1,
              :year_ratio => 0.0
            }
          }

          Spatial.score(sections, ideals)

          sections
        end
        
      end
    end

  end
end
