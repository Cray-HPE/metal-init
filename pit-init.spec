# Copyright 2021 Hewlett Packard Enterprise Development LP
%define install_dir /root/bin/

Name: pit-init
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}
License: HPE Proprietary
Summary: The pre-install toolkit scripts provided on the CRAY LiveCD
Version: %(cat .version)
Release: %(echo ${BUILD_METADATA})
Source: %{name}-%{version}.tar.bz2
Vendor: Hewlett Packard Enterprise Development LP

%description

%prep
%setup -n %{name}-%{version}

%build

%install
mkdir -p ${RPM_BUILD_ROOT}/%{install_dir}
cp -pvrR ./bin/* ${RPM_BUILD_ROOT}/%{install_dir} | awk '{print $3}' | sed "s/'//g" | sed "s|$RPM_BUILD_ROOT||g" | tee -a INSTALLED_FILES
cat INSTALLED_FILES | xargs -i sh -c 'test -L {} && exit || test -f $RPM_BUILD_ROOT/{} && echo {} || echo %dir {}' > INSTALLED_FILES_2

%clean

%files -f INSTALLED_FILES_2
%defattr(755,root,root)
%license LICENSE

%changelog
