defmodule AppWeb.NoClientUploadedFiles do
  use Phoenix.Component

  def display(assigns) do
    ~H"""
    <div class="flex flex-col flex-1 mt-10">
        <h2 class="text-base font-semibold leading-7 text-gray-900">Uploaded files to S3</h2>
        <p class="mt-1 text-sm leading-6 text-gray-600">
          Here is the list of uploaded files in S3. 🪣
        </p>

        <p class={"
          #{if length(@uploaded_files_to_S3) == 0 do "block" else "hidden" end}
          text-xs leading-7 text-gray-400 text-center my-10"}>
          No files uploaded.
        </p>

        <ul  phx-update="stream" id="uploaded_files_s3" role="list" class="divide-y divide-gray-100">
          <li
            :for={{dom_id,file}<- @uploaded_files_to_S3}
            id={dom_id}
            class="uploaded-s3-item relative flex justify-between gap-x-6 py-5"
          >
              <div :if={file.compressed_url && file.origin_url} class="flex gap-x-4">
                <div class="min-w-0 flex-auto">
                  <p>
                    <a
                      class="text-sm leading-6 break-all underline text-indigo-600"
                      href={file.origin_url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <img
                        class="block max-w-12 max-h-12 w-auto h-auto flex-none bg-gray-50"
                        src={file.compressed_url}
                        onerror="imgError(this);"
                      />
                    </a>
                  </p>
                </div>
              </div>
          </li>
        </ul>
      </div>
    """
  end
end
