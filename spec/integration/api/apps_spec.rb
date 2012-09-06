require 'spec_helper'
require 'tentd/core_ext/hash/slice'

describe TentD::API::Apps do
  def app
    TentD::API.new
  end

  def authorize!(*scopes)
    env['current_auth'] = stub(
      :kind_of? => true,
      :app_id => nil,
      :id => nil,
      :scopes => scopes
    )
  end

  let(:env) { Hash.new }
  let(:params) { Hash.new }

  describe 'GET /apps' do
    context 'when authorized' do
      before { authorize!(:read_apps) }

      with_mac_key = proc do
        it 'should return list of apps with mac keys' do
          expect(Fabricate(:app)).to be_saved

          json_get '/apps', params, env
          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          whitelist = %w{ mac_key_id mac_key mac_algorithm }
          body.each { |actual|
            whitelist.each { |key|
              expect(actual).to have_key(key)
            }
          }
        end
      end

      without_mac_key = proc do
        it 'should return list of apps without mac keys' do
          expect(Fabricate(:app)).to be_saved

          json_get '/apps', params, env
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          blacklist = %w{ mac_key_id mac_key mac_algorithm }
          body.each { |actual|
            blacklist.each { |key|
              expect(actual).to_not have_key(key)
            }
          }
        end
      end

      context 'when read_secrets scope authorized' do
        before { authorize!(:read_apps, :read_secrets) }
        context 'with secrets param' do
          before { params['secrets'] = true }
          context '', &with_mac_key
        end

        context 'without secrets param', &without_mac_key
      end

      context 'when read_secrets scope unauthorized', &without_mac_key
    end

    context 'when unauthorized' do
      it 'should respond 403' do
        json_get '/apps', params, env
        expect(last_response.status).to eq(403)
      end

      context 'when pretending to be authorized' do
        let(:_app) { Fabricate(:app) }
        before do
          env['current_auth'] = Fabricate(:app_authorization, :app => _app)
        end

        it 'should respond 403' do
          json_get "/apps?app_id=#{ _app.public_id }", params, env
          expect(last_response.status).to eq(403)
        end
      end
    end
  end

  describe 'GET /apps/:id' do
    without_mac_key = proc do
      it 'should return app without mac_key' do
        app = _app

        json_get "/apps/#{app.public_id}", params, env
        expect(last_response.status).to eq(200)
        body = JSON.parse(last_response.body)
        blacklist = %w{ mac_key_id mac_key mac_algorithm }
        blacklist.each { |key|
          expect(body).to_not have_key(key)
        }
        expect(body['id']).to eq(app.public_id)
      end
    end

    context 'when authorized via scope' do
      let(:_app) { Fabricate(:app) }
      before { authorize!(:read_apps) }

      context 'app with :id exists' do
        context 'when read_secrets scope authorized' do
          before { authorize!(:read_apps, :read_secrets) }

          context 'with read secrets param' do
            before { params['secrets'] = true }

            it 'should return app with mac_key' do
              app = _app
              json_get "/apps/#{app.public_id}", params, env
              expect(last_response.status).to eq(200)
              body = JSON.parse(last_response.body)
              whitelist = %w{ mac_key_id mac_key mac_algorithm }
              whitelist.each { |key|
                expect(body).to have_key(key)
              }
              expect(body['id']).to eq(app.public_id)
            end
          end

          context 'without read secrets param', &without_mac_key
        end

        context 'when read_secrets scope unauthorized', &without_mac_key
      end

      context 'app with :id does not exist' do
        it 'should return 404' do
          json_get "/apps/app-id", params, env
          expect(last_response.status).to eq(404)
        end
      end
    end

    context 'when authorized via identity' do
      let(:_app) { Fabricate(:app) }
      examples = proc do
        context 'app with :id exists' do
          context 'without secrets param', &without_mac_key
        end

        context 'app with :id does not exist' do
          it 'should return 403' do
            json_get '/apps/app-id', params, env
            expect(last_response.status).to eq(403)
          end
        end
      end

      context 'when App' do
        before do
          env['current_auth'] = _app
        end

        context &examples
      end
    end

    context 'when unauthorized' do
      it 'should respond 403' do
        json_get "/apps/app-id", params, env
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'POST /apps' do
    it 'should create app' do
      data = Fabricate.build(:app).attributes.slice(:name, :description, :url, :icon, :redirect_uris, :scopes)

      TentD::Model::App.all.destroy
      expect(lambda { json_post '/apps', data, env }).to change(TentD::Model::App, :count).by(1)

      app = TentD::Model::App.last
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      whitelist = %w{ mac_key_id mac_key mac_algorithm }
      whitelist.each { |key|
        expect(body).to have_key(key)
      }
    end
  end

  describe 'POST /apps/:id/authorizations' do
    context 'when authorized' do
      before { authorize!(:write_apps) }

      it 'should create app authorization' do
        app = Fabricate(:app)
        scopes = %w{ read_posts write_posts }
        post_types = %w{ https://tent.io/types/post/status https://tent.io/types/post/photo }
        profile_info_types = %w{ https://tent.io/types/info/basic https://tent.io/types/info/core }
        data = {
          :scopes => scopes,
          :post_types => post_types.map {|url| URI.encode(url, ":/") },
          :profile_info_types => profile_info_types.map {|url| URI.encode(url, ":/") },
        }
        expect(lambda {
          json_post "/apps/#{app.public_id}/authorizations", data, env
        }).to change(TentD::Model::AppAuthorization, :count)

        app_auth = app.authorizations.last
        expect(app_auth.scopes).to eq(scopes)
        expect(app_auth.post_types).to eq(post_types)
        expect(app_auth.profile_info_types).to eq(profile_info_types)
      end
    end

    context 'when not authorized' do
      context 'when token exchange' do
        it 'should exchange mac_key_id for mac_key' do
          app = Fabricate(:app)
          authorization = app.authorizations.create

          data = {
            :code => authorization.token_code
          }

          json_post "/apps/#{app.public_id}/authorizations", data, env
          expect(last_response.status).to eq(200)
          expect(authorization.reload.token_code).to_not eq(data[:code])
          body = JSON.parse(last_response.body)
          whitelist = %w{ access_token mac_key mac_algorithm token_type }
          whitelist.each { |key|
            expect(body).to have_key(key)
          }
        end
      end

      it 'should return 403' do
        app = Fabricate(:app)
        expect(lambda {
          json_post "/apps/#{app.public_id}/authorizations", params, env
        }).to_not change(TentD::Model::AppAuthorization, :count)
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'PUT /apps/:id' do
    authorized_examples = proc do
      context 'app with :id exists' do
        it 'should update app' do
          app = _app
          data = app.attributes.slice(:name, :url, :icon, :redirect_uris, :scopes)
          data[:name] = "Yet Another MicroBlog App"
          data[:scopes] = {
            "read_posts" => "Can read your posts"
          }

          json_put "/apps/#{app.public_id}", data, env
          expect(last_response.status).to eq(200)
          app.reload
          data.slice(:name, :scopes, :url, :icon, :redirect_uris).each_pair do |key, val|
            expect(app.send(key).to_json).to eq(val.to_json)
          end
        end
      end
    end

    context 'when authorized via scope' do
      let(:_app) { Fabricate(:app) }
      before { authorize!(:write_apps) }

      context '', &authorized_examples

      context 'app with :id does not exist' do
        it 'should return 404' do
          json_put "/apps/#{(TentD::Model::App.count + 1) * 100}", params, env
          expect(last_response.status).to eq(404)
        end
      end
    end

    context 'when authorized as app' do
      let(:_app) { Fabricate(:app) }

      before do
        env['current_auth'] = _app
      end

      context '', &authorized_examples

      context 'app with :id does not exist' do
        it 'should return 403' do
          json_put "/apps/app-id", params, env
          expect(last_response.status).to eq(403)
        end
      end
    end

    context 'when unauthorized' do
      it 'should respond 403' do
        json_put '/apps/app-id', params, env
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'DELETE /apps/:id' do
    authorized_examples = proc do
      context 'app with :id exists' do
        it 'should delete app' do
          app = _app
          expect(app).to be_saved

          expect(lambda {
            delete "/apps/#{app.public_id}", params, env
            expect(last_response.status).to eq(200)
          }).to change(TentD::Model::App, :count).by(-1)
        end
      end
    end

    context 'when authorized via scope' do
      before { authorize!(:write_apps) }
      let(:_app) { Fabricate(:app) }

      context '', &authorized_examples
      context 'app with :id does not exist' do
        it 'should return 404' do
          delete "/apps/app-id", params, env
          expect(last_response.status).to eq(404)
        end
      end
    end

    context 'when authorized via identity' do
      let(:_app) { Fabricate(:app) }
      before do
        env['current_auth'] = _app
      end

      context '', &authorized_examples

      context 'app with :id does not exist' do
        it 'should respond 403' do
          delete '/apps/app-id', params, env
          expect(last_response.status).to eq(403)
        end
      end
    end

    context 'when unauthorized' do
      it 'should respond 403' do
        delete '/apps/app-id', params, env
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'DELETE /apps/:app_id/authorizations/:auth_id' do
    let!(:_app) { Fabricate(:app) }
    let!(:app_auth) { Fabricate(:app_authorization, :app => _app) }
    context 'when authorized via scope' do
      before { authorize!(:write_apps) }

      it 'should delete app authorization' do
        expect(lambda {
          expect(lambda {
            delete "/apps/#{_app.public_id}/authorizations/#{app_auth.id}", params, env
          }).to_not change(TentD::Model::App, :count)
          expect(last_response.status).to eq(200)
        }).to change(TentD::Model::AppAuthorization, :count).by(-1)
      end

      it 'should return 404 unless app and authorization exist' do
        expect(lambda {
          expect(lambda {
            delete "/apps/app-id/authorizations/#{app_auth.id}", params, env
            expect(last_response.status).to eq(404)
          }).to_not change(TentD::Model::App, :count)
        }).to_not change(TentD::Model::AppAuthorization, :count)

        expect(lambda {
          expect(lambda {
            delete "/apps/#{_app.public_id}/authorizations/auth-id", params, env
            expect(last_response.status).to eq(404)
          }).to_not change(TentD::Model::App, :count)
        }).to_not change(TentD::Model::AppAuthorization, :count)
      end
    end

    context 'when not authorized' do
      it 'it should return 403' do
        expect(lambda {
          expect(lambda {
            delete "/apps/#{_app.public_id}/authorizations/#{app_auth.id}", params, env
          }).to_not change(TentD::Model::App, :count)
          expect(last_response.status).to eq(403)
        }).to_not change(TentD::Model::AppAuthorization, :count)
      end
    end
  end
end
