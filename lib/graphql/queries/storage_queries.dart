class StorageQueries {
  static const String uploadFile = r'''
    mutation Storage_UploadFile($input: UploadFileInput!) {
      Storage_UploadFile(input: $input) {
        url
        key
        filename
        mimeType
        size
      }
    }
  ''';

  static const String uploadImageWithThumbnail = r'''
    mutation Storage_UploadImageWithThumbnail($input: UploadFileInput!) {
      Storage_UploadImageWithThumbnail(input: $input) {
        url
        key
        thumbnailUrl
        thumbnailKey
        filename
        mimeType
        size
      }
    }
  ''';
}
