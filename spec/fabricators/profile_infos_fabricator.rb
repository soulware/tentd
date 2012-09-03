Fabricator(:profile_info, :class_name => 'TentServer::Model::ProfileInfo') do |f|
  f.transient :tent
  f.entity "https://johnsmith.example.org"
  f.public true
  f.type do |attrs|
    if attrs[:tent]
      "https://tent.io"
    else
      "https://tent.io/types/info-types/basic-info"
    end
  end
  f.content do |attrs|
    if attrs[:tent]
      {
        "licenses" => [
          "http://creativecommons.org/licenses/by-nc-sa/3.0/",
          "http://www.gnu.org/copyleft/gpl.html"
        ],
        "entity" => attrs[:entity],
        "servers" => [
          attrs[:entity],
          "https://backup-johnsmith.example.com"
        ]
      }
    else
      {
        "name" => "John Smith",
        "age" => 25
      }
    end
  end
end
