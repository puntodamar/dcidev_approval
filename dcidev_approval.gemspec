Gem::Specification.new do |s|
    s.name = "dcidev_approval"
    s.version = "0.0.9"
    # s.date = ""
    s.summary = "Logic for implementing record changes approval"
    s.description = "Testing phase"
    s.authors = ["Punto Damar P"]
    s.email = ["punto@privyid.tech"]
    s.files = Dir["{bin,lib}/**/*", "README.md"]
    s.require_paths = ["lib"]

    s.add_dependency 'dcidev_active_record'
  end
