require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"
require 'source_controller'

class ProductTests < ActionDispatch::IntegrationTest 
  fixtures :all
  
  def test_simple_product_file
    login_tom
    put "/source/home:tom:temporary/_meta",
        '<project name="home:tom:temporary"> <title/> <description/> 
           <repository name="me" />
         </project>'
    assert_response :success
    put "/source/home:tom:temporary/_product/_meta",
        '<package project="home:tom:temporary" name="_product"> <title/> <description/> 
            <person userid="adrian" role="maintainer" />
         </package>'
    assert_response :success
    put "/source/home:tom:temporary:link/_meta",
        '<project name="home:tom:temporary:link"> <title/> <description/> 
           <link project="home:tom:temporary" />
           <repository name="me" />
         </project>'
    assert_response :success

    # everything works even when the project is not owner by me?
    login_adrian
    # upload sources in right order
    ["defaults-archsets.include", "defaults-conditionals.include", "defaults-repositories.include", "obs.group", "obs-release.spec", "simple.product"].each do |file|
      raw_put "/source/home:tom:temporary/_product/#{file}",
              File.open("#{Rails.root}/test/fixtures/backend/source/simple_product/#{file}").read()
      assert_response :success
    end

    # product views in a project
    get "/source/home:tom:temporary?view=productlist"
    assert_response :success
    assert_xml_tag :tag => "product", 
                   :attributes => { :name => "simple", :cpe => "cpe:/o:obs_fuzzies:simple:13.1", :originproject => "home:tom:temporary" }
    get "/source/home:tom:temporary?view=productlist&expand=1"
    assert_response :success
    assert_xml_tag :tag => "product", 
                   :attributes => { :name => "simple", :cpe => "cpe:/o:obs_fuzzies:simple:13.1", :originproject => "home:tom:temporary" }

    # product views via project links
    get "/source/home:tom:temporary:link?view=productlist"
    assert_response :success
    assert_no_xml_tag :tag => "product"
    get "/source/home:tom:temporary:link?view=productlist&expand=1"
    assert_response :success
    assert_xml_tag :tag => "product", 
                   :attributes => { :name => "simple", :cpe => "cpe:/o:obs_fuzzies:simple:13.1", :originproject => "home:tom:temporary" }

    # productrepositories
    get "/source/home:tom:temporary:link/_product?view=productrepositories"
    assert_response :success
    assert_xml_tag :parent => { :tag => "repository", :attributes => { :path => '/BaseDistro2.0:/LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo' } },
                   :tag => "update"
    assert_xml_tag :tag => "repository", :attributes => { :path => '/BaseDistro/BaseDistro_repo/repo/DVD' }
    assert_xml_tag :tag => "repository", :attributes => { :url => 'http://external.url/to.some.one' }

    # product views in a package
    get "/source/home:tom:temporary/_product?view=issues"
    assert_response :success
    assert_xml_tag :tag => "kind", :content => "product"
    get "/source/home:tom:temporary/_product?view=products"
    assert_response :success
    assert_xml_tag :parent => { :tag => "product" },
                   :tag => "name", :content => "simple"
    get "/source/home:tom:temporary/_product?view=products&product=simple"
    assert_response :success
    assert_xml_tag :tag => "name", :content => "simple"
    get "/source/home:tom:temporary/_product?view=products&product=DOES_NOT_EXIST"
    assert_response :success
    assert_no_xml_tag :tag => "name", :content => "simple"

    product = Package.find_by_project_and_name("home:tom:temporary","_product").products.first
    assert_equal "simple", product.name
    assert_equal "cpe:/o:obs_fuzzies:simple:13.1", product.cpe
    assert_equal product.product_update_repositories.first.repository.project.name, "BaseDistro2.0:LinkedUpdateProject"
    assert_equal product.product_update_repositories.first.repository.name, "BaseDistro2LinkedUpdateProject_repo"

    get "/source/home:tom:temporary/_product:simple-release/simple-release.spec"
    assert_response :success
    get "/source/home:tom:temporary/_product:simple-cd-cd-i586_x86_64/simple-cd-cd-i586_x86_64.kiwi"
    assert_response :success
    assert_xml_tag :tag => "source", :attributes => { :path => "obs://home:Iggy/10.2" },
                   :parent => { :tag => "instrepo", :attributes => { :name => "repository_1", :priority => "1", :local => "true" } }
    assert_xml_tag :tag => "repopackage", :attributes => { :name => "skelcd-obs", :medium => "0", :removearch => "src,nosrc", :onlyarch => "i586,x86_64" },
                   :parent => { :tag => "metadata" }
    assert_xml_tag :tag => "repopackage", :attributes => { :name => "patterns-obs", :medium => "0", :removearch => "src,nosrc", :onlyarch => "i586,x86_64" },
                   :parent => { :tag => "metadata" }
    get "/source/home:tom:temporary/_product:simple-cd-cd-i586_x86_64/simple-cd-cd-i586_x86_64.kwd"
    assert_response :success
    assert_match(/^obs-server: \+Kwd:\\nsupport_l3\\n-Kwd:/, @response.body)

    # indexed data
    pkg=Package.find_by_project_and_name("home:tom:temporary", "_product")
    assert_not_nil pkg
    product=Product.find_by_name_and_package("simple", pkg)
    assert_not_nil product
    assert_equal product.count, 1
    product = product.first
    assert_equal product.name, "simple"
    assert_equal product.cpe, "cpe:/o:obs_fuzzies:simple:13.1"
    assert_equal product.product_update_repositories.count, 1
    pu = product.product_update_repositories.first
    assert_equal pu.repository.project.name, "BaseDistro2.0:LinkedUpdateProject"
    assert_equal pu.repository.name, "BaseDistro2LinkedUpdateProject_repo"
    assert_equal product.product_media.count, 1
    pm = product.product_media.first
    assert_equal pm.repository.project.name, "BaseDistro"
    assert_equal pm.repository.name, "BaseDistro_repo"

    # invalid uploads 
    raw_put "/source/home:tom:temporary/_product/obs.group",
      File.open("#{Rails.root}/test/fixtures/backend/source/simple_product/INVALID_obs.group").read()
    assert_response 400
    assert_xml_tag :tag => "status", :attributes => { :code => '400', :origin => 'backend' }
    assert_match(/Illegal support key ILLEGAL for obs-server/, @response.body)

    login_tom
    delete "/source/home:tom:temporary:link"
    assert_response :success
    delete "/source/home:tom:temporary"
    assert_response :success
  end

  def test_sle11_product_file
    login_tom
    put "/source/home:tom:temporary/_meta",
        '<project name="home:tom:temporary"> <title/> <description/> 
         </project>'
    assert_response :success
    put "/source/home:tom:temporary/_product/_meta",
        '<package project="home:tom:temporary" name="_product"> <title/> <description/> 
            <person userid="adrian" role="maintainer" />
         </package>'
    assert_response :success
    put "/source/home:tom:temporary:link/_meta",
        '<project name="home:tom:temporary:link"> <title/> <description/> 
           <link project="home:tom:temporary" />
           <repository name="me">
             <arch>x86_64</arch>
           </repository>
         </project>'
    assert_response :success
    # and set release target
    put "/source/home:tom:temporary/_meta",
        '<project name="home:tom:temporary"> <title/> <description/> 
           <repository name="me" >
             <releasetarget project="home:tom:temporary:link" repository="me" trigger="manual" />
             <arch>x86_64</arch>
           </repository>
         </project>'
    assert_response :success

    # everything works even when the project is not owner by me?
    login_adrian
    # upload sources in right order
    ["defaults-archsets.include", "defaults-conditionals.include", "defaults-repositories.include", "obs.group", "obs-release.spec", "SUSE_SLES.product"].each do |file|
      raw_put "/source/home:tom:temporary/_product/#{file}",
              File.open("#{Rails.root}/test/fixtures/backend/source/sle11_product/#{file}").read()
      assert_response :success
    end

    # product views in a project
    get "/source/home:tom:temporary?view=productlist"
    assert_response :success
    assert_xml_tag :tag => "product", 
                   :attributes => { :name => "SUSE_SLES", :cpe => "cpe:/a:suse:suse_sles:11.2", :originproject => "home:tom:temporary" }
    get "/source/home:tom:temporary?view=productlist&expand=1"
    assert_response :success
    assert_xml_tag :tag => "product", 
                   :attributes => { :name => "SUSE_SLES", :cpe => "cpe:/a:suse:suse_sles:11.2", :originproject => "home:tom:temporary" }

    # product views via project links
    get "/source/home:tom:temporary:link?view=productlist"
    assert_response :success
    assert_no_xml_tag :tag => "product"
    get "/source/home:tom:temporary:link?view=productlist&expand=1"
    assert_response :success
    assert_xml_tag :tag => "product", 
                   :attributes => { :name => "SUSE_SLES", :cpe => "cpe:/a:suse:suse_sles:11.2", :originproject => "home:tom:temporary" }

    # product views in a package
    get "/source/home:tom:temporary/_product?view=issues"
    assert_response :success
    assert_xml_tag :tag => "kind", :content => "product"
    get "/source/home:tom:temporary/_product?view=products"
    assert_response :success
    assert_xml_tag :parent => { :tag => "product", :attributes => { :id => 'simple' } },
                   :tag => "name", :content => "SUSE_SLES"
    get "/source/home:tom:temporary/_product?view=products&product=SUSE_SLES"
    assert_response :success
    assert_xml_tag :tag => "name", :content => "SUSE_SLES"
    get "/source/home:tom:temporary/_product?view=products&product=DOES_NOT_EXIST"
    assert_response :success
    assert_no_xml_tag :tag => "name"
    # productrepositories
    get "/source/home:tom:temporary/_product?view=productrepositories"
    assert_response :success
    assert_xml_tag :parent => { :tag => "repository", :attributes => { :path => '/BaseDistro2.0:/LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo' } },
                   :tag => "update",
                   :tag => "zypp", :attributes => { :name => "basedistro2 update distribution", :alias => "basedistro2_alias" }
    assert_xml_tag :tag => "distrotarget", :attributes => { :arch => "x86_64" }, :content => "DiStroTarGet_x86"
    assert_xml_tag :tag => "distrotarget", :content => "DiStroTarGet"

    product = Package.find_by_project_and_name("home:tom:temporary","_product").products.first
    assert_equal "SUSE_SLES", product.name
    assert_equal "cpe:/a:suse:suse_sles:11.2", product.cpe
    assert_equal product.product_update_repositories.first.repository.project.name, "BaseDistro2.0:LinkedUpdateProject"
    assert_equal product.product_update_repositories.first.repository.name, "BaseDistro2LinkedUpdateProject_repo"

    get "/source/home:tom:temporary/_product:SUSE_SLES-SP3-migration/SUSE_SLES-SP3-migration.spec"
    assert_response :success
    get "/source/home:tom:temporary/_product:SUSE_SLES-release/SUSE_SLES-release.spec"
    assert_response :success
    get "/source/home:tom:temporary/_product:sle-obs-cd-cd-i586_x86_64/sle-obs-cd-cd-i586_x86_64.kiwi"
    assert_response :success
    assert_xml_tag :tag => "source", :attributes => { :path => "obs://home:Iggy/10.2" },
                   :parent => { :tag => "instrepo", :attributes => { :name => "repository_1", :priority => "1", :local => "true" } }
    assert_xml_tag :tag => "repopackage", :attributes => { :name => "skelcd-obs", :medium => "0", :removearch => "src,nosrc", :onlyarch => "i586,x86_64" },
                   :parent => { :tag => "metadata" }
    assert_xml_tag :tag => "repopackage", :attributes => { :name => "patterns-obs", :medium => "0", :removearch => "src,nosrc", :onlyarch => "i586,x86_64" },
                   :parent => { :tag => "metadata" }
    get "/source/home:tom:temporary/_product:sle-obs-cd-cd-i586_x86_64/sle-obs-cd-cd-i586_x86_64.kwd"
    assert_response :success
    assert_match(/^obs-server: \+Kwd:\\nsupport_l3\\n-Kwd:/, @response.body)

    # release product
    login_tom
    get "/source/home:tom:temporary:link"
    assert_response :success
    assert_xml_tag :tag => "directory", :attributes => { :count => "0" }
    post "/source/home:tom:temporary/_product:sle-obs-cd-cd-i586_x86_64?cmd=release"
    assert_response :success
    get "/source/home:tom:temporary:link"
    assert_response :success
    assert_xml_tag :tag => "entry", :attributes => { :name => "_product:sle-obs-cd-cd-i586_x86_64" },
                   :parent => { :tag => "directory", :attributes => { :count => "4" } }
    # FIXME: add tests for release number handling with various products, requires product binaries and trees

    # remove product and check that _product: get removed as well.
    get "/source/home:tom:temporary/_product:SUSE_SLES-release"
    assert_response :success
    delete "/source/home:tom:temporary/_product"
    assert_response :success
    get "/source/home:tom:temporary/_product:SUSE_SLES-release"
    assert_response 404

    #cleanup
    delete "/source/home:tom:temporary:link?force=1"
    assert_response :success
    delete "/source/home:tom:temporary"
    assert_response :success
  end

end
