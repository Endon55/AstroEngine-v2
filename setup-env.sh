#!/bin/bash



#add odin and add to path
#add vulkan, might need path?

#add premake and other dependencies
#build imgui, vkb, and vma

#build glfw as well

project_dir=$(pwd)
src="/usr/local/src"
bin="/usr/local/bin"
libs="$project_dir/libs"
usr=${SUDO_USER:-$(whoami)}
home="/home/$usr"
echo $id
cd /usr/local/

mkdir -p src

echo "Setting up environment"
sudo apt install llvm-20 clang python3-venv python3-pip libwayland-dev libxkbcommon-dev xorg-dev libvulkan-dev vulkan-tools vulkan-validationlayers spirv-tools libvulkan1 mesa-vulkan-drivers

cd $src
if [ ! -e "$src/odin" ]; then
    echo "Downloading Odin"
    sudo git clone https://github.com/odin-lang/Odin odin
fi

if [ ! -e "$src/odin/odin" ]; then
    echo "Building odin"
    cd odin
    ./build_odin.sh
fi

if [ ! -e "$bin/odin" ]; then
    echo "Adding odin to path"
    ln -s $src/odin/odin $bin
fi

cd $src
mkdir -p vulkan

cd vulkan
vulkan_sdk_version=$(curl -s https://vulkan.lunarg.com/sdk/latest/linux.txt)
echo $vulkan_sdk_version
if [ -z "$(ls -A .)" ]; then
    echo Downloading Vulkan SDK:$vulkan_sdk_version
    curl -L https://sdk.lunarg.com/sdk/download/${vulkan_sdk_version}/linux/vulkansdk-linux-x86_64-${vulkan_sdk_version}.tar.xz | tar -xJ
else
    for file in *; do
        vulkan_sdk_version=$file
        echo $vulkan_sdk_version
    done
fi
if grep -Fxq "export PATH=\"$src/vulkan/$vulkan_sdk_version/x86_64/bin:\$PATH\"" $home/.bashrc; then
    echo "Adding Vulkan to path"
    echo "export PATH=\"$src/vulkan/$vulkan_sdk_version/x86_64/bin:\$PATH\"" >> $home/.bashrc
fi


cd $src
if [ ! -e "$src/premake" ]; then
    echo "Downloading premake5"
    sudo git clone https://github.com/premake/premake-core premake
fi

premake_path="/usr/local/src/premake/bin/release"
if [ ! -e "$src/premake/bin/release/premake5" ]; then
    echo "Building premake5"
    cd premake
    chmod +x Bootstrap.sh
    ./Bootstrap.sh
fi
if [ ! -e "$bin/premake5" ]; then
    echo "Adding premake5 to path"
    ln -s $src/premake/bin/release/premake5 $bin 
fi

source $home/.bashrc

cd $project_dir/libs

echo "Building project libs"

cd $libs/imgui

if [ ! -e "$libs/imgui/libimgui_*.a" ]; then
    echo "Building ImGui"
    
    premake5 --backends=glfw,vulkan gmake
    cd build/make/linux
    make config=release_x86_64
fi


cd $libs/vma

if [ ! -e "$libs/vma/*.a" ]; then
    echo "Building VMA"
    
    premake5 --vk-version=3 gmake
    cd build/make/linux
    make config=release_x86_64
fi



cd $libs/glfw

mkdir -p build

if [ ! -e "$libs/glfw/build/src/libglfw3.a" ]; then
    echo "Building GLFW"
    cmake -S . -B build
    cd build
    make

fi

cd $src/odin/vendor/glfw/lib

if [ ! -e "$src/odin/vendor/glfw/lib/libglfw3.a" ]; then
    echo "Adding custom GLFW binary to odin"
    
    ln -s $libs/glfw/build/src/libglfw3.a .
fi

exec bash
