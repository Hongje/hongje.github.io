require 'cgi'

module Jekyll
  module PublicationAuthors
    CONTRIBUTION_MARKERS = /[*\u2020\u2021\u00A7]+/.freeze

    def publication_authors(entry)
      authors = parse_publication_authors(author_source(entry))
      site = @context.registers[:site]

      authors.each_with_index.map do |author, index|
        html = format_publication_author(author, site)

        if authors.length == 1
          html
        elsif index == authors.length - 1
          "and #{html}"
        else
          "#{html},&nbsp;"
        end
      end.join
    end

    private

    def author_source(entry)
      bibtex = value_from(entry, :bibtex)
      author = field_from_bibtex(bibtex, 'author')
      return author unless blank?(author)

      author = value_from(entry, :author)
      return author.to_s unless blank?(author)

      author = indexed_value_from(entry, 'author')
      return author.to_s unless blank?(author)

      indexed_value_from(entry, :author).to_s
    end

    def value_from(entry, key)
      return if entry.nil?

      entry.public_send(key) if entry.respond_to?(key)
    rescue StandardError
      nil
    end

    def indexed_value_from(entry, key)
      return unless entry.respond_to?(:[])

      entry[key]
    rescue StandardError
      nil
    end

    def field_from_bibtex(bibtex, field)
      return if blank?(bibtex)

      match = bibtex.match(/\b#{Regexp.escape(field)}\s*=/i)
      return unless match

      index = match.end
      index += 1 while index < bibtex.length && bibtex[index] =~ /\s/
      delimiter = bibtex[index]

      case delimiter
      when '{'
        braced_value(bibtex, index)
      when '"'
        quoted_value(bibtex, index)
      else
        bibtex[index..].to_s.split(',', 2).first
      end
    end

    def braced_value(text, start_index)
      depth = 0
      value = +''

      text[start_index..].each_char.with_index(start_index) do |char, index|
        if char == '{'
          depth += 1
          value << char if depth > 1
        elsif char == '}'
          depth -= 1
          return value if depth.zero?

          value << char
        elsif index > start_index
          value << char
        end
      end

      value
    end

    def quoted_value(text, start_index)
      value = +''
      escaped = false

      text[(start_index + 1)..].to_s.each_char do |char|
        if escaped
          value << char
          escaped = false
        elsif char == '\\'
          escaped = true
          value << char
        elsif char == '"'
          return value
        else
          value << char
        end
      end

      value
    end

    def parse_publication_authors(author_text)
      text = clean_author_text(author_text)
      return [] if text.empty?

      names =
        if text.match?(/\s+\band\b\s+/i)
          text.split(/\s+\band\b\s+/i).map { |name| parse_bibtex_or_natural_name(name) }
        else
          comma_parts = split_author_commas(text)
          if old_style_single_author?(comma_parts)
            [parse_bibtex_or_natural_name(text)]
          else
            comma_parts.map { |name| parse_natural_name(name) }
          end
        end

      names.reject { |author| blank?(author[:display]) }
    end

    def clean_author_text(author_text)
      author_text.to_s
                 .gsub(/\A\s*[{"]|[}"]\s*\z/, '')
                 .gsub(/\s+/, ' ')
                 .strip
    end

    def split_author_commas(text)
      text.split(/\s*,\s*/).map(&:strip).reject(&:empty?)
    end

    def old_style_single_author?(comma_parts)
      comma_parts.length == 2 && !comma_parts.first.match?(/\s/)
    end

    def parse_bibtex_or_natural_name(name)
      cleaned = clean_author_text(name)

      if cleaned.include?(',')
        last, first = cleaned.split(',', 2).map(&:strip)
        author_hash(first, last)
      else
        parse_natural_name(cleaned)
      end
    end

    def parse_natural_name(name)
      cleaned = clean_author_text(name)
      parts = cleaned.split(/\s+/)

      if parts.length <= 1
        author_hash('', cleaned)
      else
        last = parts.pop
        author_hash(parts.join(' '), last)
      end
    end

    def author_hash(first, last)
      first = first.to_s.strip
      last = last.to_s.strip
      display = [first, last].reject(&:empty?).join(' ')

      { first: first, last: last, display: display }
    end

    def format_publication_author(author, site)
      display = escape(author[:display])

      if self_author?(author, site)
        "<em>#{display}</em>"
      elsif (url = coauthor_url(author, site))
        %(<a href="#{escape(url)}">#{display}</a>)
      else
        display
      end
    end

    def self_author?(author, site)
      scholar = site.config['scholar'] || {}
      scholar_last = scholar['last_name'].to_s
      scholar_first = scholar['first_name'].to_s

      normalized_last(author[:last]) == normalized_last(scholar_last) &&
        scholar_first.include?(author[:first].to_s)
    end

    def coauthor_url(author, site)
      coauthors = site.data['coauthors'] || {}
      matches = coauthors[author[:first].to_s]
      return unless matches

      clean_last = normalized_last(author[:last])
      match = matches.find do |coauthor|
        Array(coauthor['lastname']).map { |name| normalized_last(name) }.include?(clean_last)
      end

      match && match['url']
    end

    def normalized_last(last)
      last.to_s.gsub(CONTRIBUTION_MARKERS, '').strip
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end

Liquid::Template.register_filter(Jekyll::PublicationAuthors)
