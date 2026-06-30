require 'cgi'

module Jekyll
  module PublicationAuthors
    CONTRIBUTION_MARKERS = /[*\u2020\u2021\u00A7]+/.freeze

    def publication_authors(entry, key = nil, title = nil)
      site = @context.registers[:site]
      authors = parsed_publication_authors(entry, site, key, title)

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

    def parsed_publication_authors(entry, site, key = nil, title = nil)
      author_sources(entry, site, key, title).each do |source|
        authors = parse_publication_authors(source)
        return authors unless authors.empty?
      end

      []
    end

    def author_sources(entry, site, key = nil, title = nil)
      bibtex = value_from(entry, :bibtex)
      [
        author_from_bibliography_file(entry, site, key, title),
        field_from_bibtex(bibtex, 'author'),
        value_from(entry, :author),
        indexed_value_from(entry, 'author'),
        indexed_value_from(entry, :author)
      ].reject { |author| blank?(author) }.map(&:to_s)
    end

    def author_from_bibliography_file(entry, site, explicit_key = nil, explicit_title = nil)
      key = entry_key(entry, explicit_key)
      title = entry_title(entry, explicit_title)
      return if (blank?(key) && blank?(title)) || site.nil?

      bibliography_paths(site).each do |path|
        next unless File.file?(path)

        text = read_bibliography_file(path)
        raw_entry = blank?(key) ? nil : bibtex_entry_from_file(text, key)
        raw_entry ||= bibtex_entry_with_field_from_file(text, 'title', title) unless blank?(title)
        author = field_from_bibtex(raw_entry, 'author')
        return author unless blank?(author)
      end

      nil
    rescue StandardError
      nil
    end

    def entry_key(entry, explicit_key = nil)
      [
        explicit_key,
        value_from(entry, :key),
        indexed_value_from(entry, 'key'),
        indexed_value_from(entry, :key),
        value_from(entry, :id),
        indexed_value_from(entry, 'id'),
        indexed_value_from(entry, :id)
      ].find { |key| !blank?(key) }.to_s
    end

    def entry_title(entry, explicit_title = nil)
      [
        explicit_title,
        value_from(entry, :title),
        indexed_value_from(entry, 'title'),
        indexed_value_from(entry, :title)
      ].find { |title| !blank?(title) }.to_s
    end

    def bibliography_paths(site)
      scholar = site.config['scholar'] || {}
      source_dir = scholar['source'].to_s
      source_dir = '_bibliography' if blank?(source_dir)
      source_dir = source_dir.sub(%r{\A/+}, '').sub(%r{/+\z}, '')

      bibliographies = Array(scholar['bibliography']).reject { |path| blank?(path) }
      bibliographies = ['papers.bib'] if bibliographies.empty?

      site_source = site.respond_to?(:source) ? site.source : Dir.pwd
      bibliographies.map { |bibliography| File.join(site_source, source_dir, bibliography.to_s) }
    end

    def bibtex_entry_from_file(text, key)
      text = text.to_s
      match = text.match(/@\w+\s*\{\s*#{Regexp.escape(key)}\s*,/i)
      return unless match

      start_index = match.begin(0)
      bibtex_entry_at(text, start_index)
    end

    def bibtex_entry_with_field_from_file(text, field, value)
      normalized_value = normalized_lookup_value(value)
      return if normalized_value.empty?

      bibtex_entries_from_file(text).find do |entry|
        normalized_lookup_value(field_from_bibtex(entry, field)) == normalized_value
      end
    end

    def bibtex_entries_from_file(text)
      text = text.to_s
      entries = []
      offset = 0

      while (match = text.match(/@\w+\s*\{/, offset))
        entry = bibtex_entry_at(text, match.begin(0))
        entries << entry unless blank?(entry)
        offset = match.end(0)
      end

      entries
    end

    def bibtex_entry_at(text, start_index)
      open_index = text.index('{', start_index)
      return unless open_index

      depth = 0
      text[open_index..].each_char.with_index(open_index) do |char, index|
        depth += 1 if char == '{'
        depth -= 1 if char == '}'

        return text[start_index..index] if depth.zero?
      end

      text[start_index..]
    end

    def read_bibliography_file(path)
      File.open(path, 'r:bom|utf-8') { |file| file.read }
    end

    def normalized_lookup_value(value)
      CGI.unescapeHTML(value.to_s)
         .gsub(/<[^>]*>/, '')
         .gsub(/[{}"]/, '')
         .gsub(/\s+/, ' ')
         .strip
         .downcase
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

      bibtex = bibtex.to_s
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
      display = publication_escape(author[:display])

      if self_author?(author, site)
        "<em>#{display}</em>"
      elsif (url = coauthor_url(author, site))
        %(<a href="#{publication_escape(url)}">#{display}</a>)
      else
        display
      end
    end

    def self_author?(author, site)
      scholar = site.config['scholar'] || {}
      scholar_last = scholar['last_name'].to_s
      scholar_first = normalized_name(scholar['first_name'])
      author_first = normalized_name(author[:first])

      normalized_last(author[:last]) == normalized_last(scholar_last) &&
        (author_first.empty? || scholar_first.include?(author_first))
    end

    def coauthor_url(author, site)
      coauthors = site.data['coauthors'] || {}
      clean_first = normalized_name(author[:first])
      _, matches = coauthors.find do |first, _coauthor_matches|
        normalized_name(first) == clean_first
      end
      return unless matches

      clean_last = normalized_last(author[:last])
      match = matches.find do |coauthor|
        Array(coauthor['lastname']).map { |name| normalized_last(name) }.include?(clean_last)
      end

      match && match['url']
    end

    def normalized_last(last)
      normalized_name(last)
    end

    def normalized_name(name)
      CGI.unescapeHTML(name.to_s)
         .gsub(/\\(?:textsuperscript|ensuremath)\s*\{?\s*\\?(?:dagger|ddagger|ast|asterisk|S|section)\s*\}?/i, '')
         .gsub(/\\(?:dagger|ddagger|ast|asterisk|S|section)\b/i, '')
         .gsub(/<[^>]*>/, '')
         .gsub(/[{}]/, '')
         .gsub(CONTRIBUTION_MARKERS, '')
         .gsub(/\s+/, ' ')
         .strip
         .downcase
    end

    def publication_escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end

Liquid::Template.register_filter(Jekyll::PublicationAuthors)
