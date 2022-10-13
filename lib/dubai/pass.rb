# frozen_string_literal: true

require 'digest/sha1'
require 'openssl'
require 'base64'
require 'json'
require 'zip'

module Dubai
  module Passbook
    WWDR_CERTIFICATE = <<~EOF
      -----BEGIN CERTIFICATE-----
      MIIEVTCCAz2gAwIBAgIUE9x3lVJx5T3GMujM/+Uh88zFztIwDQYJKoZIhvcNAQEL
      BQAwYjELMAkGA1UEBhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xJjAkBgNVBAsT
      HUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRYwFAYDVQQDEw1BcHBsZSBS
      b290IENBMB4XDTIwMTIxNjE5MzYwNFoXDTMwMTIxMDAwMDAwMFowdTFEMEIGA1UE
      Aww7QXBwbGUgV29ybGR3aWRlIERldmVsb3BlciBSZWxhdGlvbnMgQ2VydGlmaWNh
      dGlvbiBBdXRob3JpdHkxCzAJBgNVBAsMAkc0MRMwEQYDVQQKDApBcHBsZSBJbmMu
      MQswCQYDVQQGEwJVUzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANAf
      eKp6JzKwRl/nF3bYoJ0OKY6tPTKlxGs3yeRBkWq3eXFdDDQEYHX3rkOPR8SGHgjo
      v9Y5Ui8eZ/xx8YJtPH4GUnadLLzVQ+mxtLxAOnhRXVGhJeG+bJGdayFZGEHVD41t
      QSo5SiHgkJ9OE0/QjJoyuNdqkh4laqQyziIZhQVg3AJK8lrrd3kCfcCXVGySjnYB
      5kaP5eYq+6KwrRitbTOFOCOL6oqW7Z+uZk+jDEAnbZXQYojZQykn/e2kv1MukBVl
      PNkuYmQzHWxq3Y4hqqRfFcYw7V/mjDaSlLfcOQIA+2SM1AyB8j/VNJeHdSbCb64D
      YyEMe9QbsWLFApy9/a8CAwEAAaOB7zCB7DASBgNVHRMBAf8ECDAGAQH/AgEAMB8G
      A1UdIwQYMBaAFCvQaUeUdgn+9GuNLkCm90dNfwheMEQGCCsGAQUFBwEBBDgwNjA0
      BggrBgEFBQcwAYYoaHR0cDovL29jc3AuYXBwbGUuY29tL29jc3AwMy1hcHBsZXJv
      b3RjYTAuBgNVHR8EJzAlMCOgIaAfhh1odHRwOi8vY3JsLmFwcGxlLmNvbS9yb290
      LmNybDAdBgNVHQ4EFgQUW9n6HeeaGgujmXYiUIY+kchbd6gwDgYDVR0PAQH/BAQD
      AgEGMBAGCiqGSIb3Y2QGAgEEAgUAMA0GCSqGSIb3DQEBCwUAA4IBAQA/Vj2e5bbD
      eeZFIGi9v3OLLBKeAuOugCKMBB7DUshwgKj7zqew1UJEggOCTwb8O0kU+9h0UoWv
      p50h5wESA5/NQFjQAde/MoMrU1goPO6cn1R2PWQnxn6NHThNLa6B5rmluJyJlPef
      x4elUWY0GzlxOSTjh2fvpbFoe4zuPfeutnvi0v/fYcZqdUmVIkSoBPyUuAsuORFJ
      EtHlgepZAE9bPFo22noicwkJac3AfOriJP6YRLj477JxPxpd1F1+M02cHSS+APCQ
      A1iZQT0xWmJArzmoUUOSqwSonMJNsUvSq3xKX+udO7xPiEAGE/+QF4oIRynoYpgp
      pU8RBWk6z/Kf
      -----END CERTIFICATE-----
    EOF

    class << self
      attr_accessor :certificate, :password
    end

    class Pass
      attr_reader :pass, :assets

      TYPES = ['boarding-pass', 'coupon', 'event-ticket', 'store-card', 'generic'].freeze

      def initialize(directory)
        @assets = Dir[File.join(directory, '*')]
        @pass = File.read(@assets.delete(@assets.detect { |file| File.basename(file) == 'pass.json' }))
      end

      def manifest
        checksums = {}
        checksums['pass.json'] = Digest::SHA1.hexdigest(@pass)

        @assets.each do |file|
          checksums[File.basename(file)] = Digest::SHA1.file(file).hexdigest
        end

        checksums.to_json
      end

      def pkpass
        Zip::OutputStream.write_buffer do |zip|
          zip.put_next_entry('pass.json') && zip.write(@pass)
          zip.put_next_entry('manifest.json') && zip.write(manifest)
          zip.put_next_entry('signature') && zip.write(signature(manifest))

          @assets.each do |file|
            zip.put_next_entry(File.basename(file)) && zip.print(IO.read(file))
          end
        end
      end

      private

      def signature(manifest)
        pk7 = OpenSSL::PKCS7.sign(p12.certificate, p12.key, manifest, [wwdr], OpenSSL::PKCS7::BINARY | OpenSSL::PKCS7::DETACHED)
        data = OpenSSL::PKCS7.write_smime(pk7)

        start = %(filename=\"smime.p7s"\n\n)
        finish = "\n\n------"
        data = data[(data.index(start) + start.length)...(data.rindex(finish) + finish.length)]

        Base64.decode64(data)
      end

      def p12
        OpenSSL::PKCS12.new(File.read(Passbook.certificate), Passbook.password)
      end

      def wwdr
        OpenSSL::X509::Certificate.new(WWDR_CERTIFICATE)
      end
    end
  end
end
