require 'dcf'
require 'zlib'
require 'rubygems/package'
namespace :packages do

  task fetch: :environment do
    current_date = Time.now.strftime("%d_%m_%Y")
    current_dir = File.expand_path File.dirname(__FILE__)

    file_name = "PACKAGES_#{current_date}"

    packages_file_name = File.join(current_dir, file_name)

    yesterday = Date.yesterday.strftime("%d_%m_%Y")
    yesterday_file_name = "PACKAGES_#{yesterday}"
    yesterday_packages_file_name = File.join(current_dir, yesterday_file_name)

    #Good idea for future - its make diff between yesterday and today index hashes and proceed with it

    @cache_dir = File.join(current_dir, 'cache')

    unless File.directory?(@cache_dir)
      FileUtils.mkdir_p(@cache_dir)
    end


    if File.file?(packages_file_name)
      p "Package index file already exists in cache - downloading skipped..."

      process_package_file(packages_file_name)
    else
      p "Package index file doesn't exists in cache - downloading started..."

      open(packages_file_name, 'wb') do |file|
        file << open('https://cran.r-project.org/src/contrib/PACKAGES').read
        p "Package index file downloaded..."
      end
      process_package_file(packages_file_name)
    end
  end


  def process_package_file(file_name)
    data = File.open(file_name, "rb") {|io| io.read}
    parsed_packages = Dcf.parse(data)

    if parsed_packages
      parsed_packages.each do |parsed_package|
        #Try to find particular package in DB
        package = Package.find_or_create_by(name: parsed_package["Package"], version: parsed_package["Version"])

        if package.version != parsed_package["Version"]
          Package.create(name: parsed_package["Package"], version: parsed_package["Version"])
        end

        package.name = parsed_package["Package"]
        package.version = parsed_package["Version"]
        if package.save
          p "Package #{package.name} with version #{package.version} has been processed"
        end
        update_packages_metadata(parsed_package)
      end
    end
  end

  def update_packages_metadata(package)

    package_filename = "#{package["Package"]}_#{package["Version"]}.tar.gz"

    package_url = "http://cran.r-project.org/src/contrib/#{package_filename}"

    download_path = File.join(@cache_dir, package_filename)

    if File.file?(download_path)
      p "Package file already exists in cache - downloading skipped..."
      process_archive_metadata(download_path, package)
    else
      open(download_path, 'wb') do |file|
        file << open(package_url).read
        p "File #{package_url} has been downloaded"
        process_archive_metadata(download_path, package)
      end
    end
  end

  def process_archive_metadata(download_path, package)
    begin
      tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(download_path))
      tar_extract.rewind
      tar_extract.each do |entry|
        if entry.file?
          filename = entry.full_name
          if filename.include? "DESCRIPTION"
            data = entry.read
            metadata = Dcf.parse(data).first
            package_in_db = Package.find_by_name(package["Package"])
            if package_in_db
              package_in_db.update(
                  title: metadata["Title"].encode("UTF-8", invalid: :replace, undef: :replace),
                  description: metadata["Description"].encode("UTF-8", invalid: :replace, undef: :replace),
                  author: metadata["Author"].encode("UTF-8", invalid: :replace, undef: :replace),
                  maintainer: metadata["Maintainer"].encode("UTF-8", invalid: :replace, undef: :replace),
                  publication_date: Date.parse(metadata["Date/Publication"])
              )
            end
          end
        end
      end
      tar_extract.close
    end
  rescue StandardError => e
    p e.message
  end

  def deep_diff(a, b)
    (a.keys | b.keys).each_with_object({}) do |k, diff|
      if a[k] != b[k]
        if a[k].is_a?(Hash) && b[k].is_a?(Hash)
          diff[k] = deep_diff(a[k], b[k])
        else
          diff[k] = [a[k], b[k]]
        end
      end
      diff
    end
  end
end
