docker build -f docker/Dockerfile --tag razor-tests --target razor-tests .
docker run -i razor-tests
