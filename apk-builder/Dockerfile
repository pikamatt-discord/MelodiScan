FROM ghcr.io/cirruslabs/flutter:3.44.0

USER root
WORKDIR /workspace/mobile

COPY scripts/apk-builder-service.py /opt/melodiscan/apk_builder.py

EXPOSE 8090
ENTRYPOINT ["python3", "/opt/melodiscan/apk_builder.py"]
